import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { Client, GatewayIntentBits, EmbedBuilder, REST, Routes, SlashCommandBuilder } from 'discord.js';
import db from './db.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' })); // Large payloads for full model data

// ============ DISCORD BOT SETUP ============
const discord = new Client({
  intents: [GatewayIntentBits.Guilds]
});

const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const DISCORD_CHANNEL_ID = process.env.DISCORD_CHANNEL_ID;
const DISCORD_GUILD_ID = process.env.DISCORD_GUILD_ID;

let botReady = false;

discord.once('ready', async () => {
  console.log(`✓ Discord bot logged in as ${discord.user.tag}`);
  botReady = true;
  
  // Register slash commands
  const commands = [
    new SlashCommandBuilder()
      .setName('lookup')
      .setDescription('Look up asset ownership by asset ID')
      .addStringOption(opt => 
        opt.setName('asset_id')
          .setDescription('The Roblox asset ID to look up')
          .setRequired(true)),
    new SlashCommandBuilder()
      .setName('user')
      .setDescription('View all assets registered to a user')
      .addStringOption(opt =>
        opt.setName('roblox_id')
          .setDescription('The Roblox user ID')
          .setRequired(true)),
    new SlashCommandBuilder()
      .setName('stats')
      .setDescription('View registry statistics')
  ].map(cmd => cmd.toJSON());

  const rest = new REST({ version: '10' }).setToken(DISCORD_TOKEN);
  try {
    await rest.put(Routes.applicationGuildCommands(discord.user.id, DISCORD_GUILD_ID), { body: commands });
    console.log('✓ Slash commands registered');
  } catch (err) {
    console.error('✗ Failed to register slash commands:', err.message);
  }
});

// Slash command handler
discord.on('interactionCreate', async interaction => {
  if (!interaction.isChatInputCommand()) return;

  if (interaction.commandName === 'lookup') {
    const assetId = interaction.options.getString('asset_id');
    try {
      const result = await db.query(
        `SELECT a.*, u.roblox_username 
         FROM assets a 
         JOIN users u ON a.owner_id = u.roblox_user_id 
         WHERE a.asset_id = $1`,
        [assetId]
      );
      if (result.rows.length === 0) {
        await interaction.reply({ content: `Asset \`${assetId}\` is not registered.`, ephemeral: true });
      } else {
        const asset = result.rows[0];
        const embed = new EmbedBuilder()
          .setTitle('Asset Lookup')
          .setColor(0x9966ff)
          .addFields(
            { name: 'Asset ID', value: assetId, inline: true },
            { name: 'Name', value: asset.name || 'Unknown', inline: true },
            { name: 'Owner', value: `${asset.roblox_username} (${asset.owner_id})`, inline: false },
            { name: 'Registered', value: new Date(asset.registered_at).toLocaleDateString(), inline: true }
          );
        await interaction.reply({ embeds: [embed] });
      }
    } catch (err) {
      await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
    }
  }

  if (interaction.commandName === 'user') {
    const robloxId = interaction.options.getString('roblox_id');
    try {
      const userResult = await db.query('SELECT * FROM users WHERE roblox_user_id = $1', [robloxId]);
      if (userResult.rows.length === 0) {
        await interaction.reply({ content: `User \`${robloxId}\` has no registered assets.`, ephemeral: true });
        return;
      }
      const user = userResult.rows[0];
      const assetsResult = await db.query('SELECT COUNT(*) as count FROM assets WHERE owner_id = $1', [robloxId]);
      const modelsResult = await db.query('SELECT COUNT(*) as count FROM models WHERE owner_id = $1', [robloxId]);
      
      const embed = new EmbedBuilder()
        .setTitle(`Registry: ${user.roblox_username}`)
        .setColor(0x9966ff)
        .addFields(
          { name: 'Roblox ID', value: robloxId, inline: true },
          { name: 'Registered Meshes', value: assetsResult.rows[0].count, inline: true },
          { name: 'Registered Models', value: modelsResult.rows[0].count, inline: true },
          { name: 'Member Since', value: new Date(user.created_at).toLocaleDateString(), inline: false }
        );
      await interaction.reply({ embeds: [embed] });
    } catch (err) {
      await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
    }
  }

  if (interaction.commandName === 'stats') {
    try {
      const users = await db.query('SELECT COUNT(*) as count FROM users');
      const assets = await db.query('SELECT COUNT(*) as count FROM assets');
      const models = await db.query('SELECT COUNT(*) as count FROM models');
      
      const embed = new EmbedBuilder()
        .setTitle('Palantir Registry Stats')
        .setColor(0x9966ff)
        .addFields(
          { name: 'Registered Users', value: users.rows[0].count, inline: true },
          { name: 'Registered Meshes', value: assets.rows[0].count, inline: true },
          { name: 'Registered Models', value: models.rows[0].count, inline: true }
        );
      await interaction.reply({ embeds: [embed] });
    } catch (err) {
      await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
    }
  }
});

// Send notification to Discord channel
async function notifyDiscord(embed) {
  if (!botReady) return;
  try {
    const channel = await discord.channels.fetch(DISCORD_CHANNEL_ID);
    if (channel) await channel.send({ embeds: [embed] });
  } catch (err) {
    console.error('Discord notification failed:', err.message);
  }
}

// ============ API ROUTES ============

// Health check
app.get('/', (req, res) => {
  res.json({ status: 'ok', service: 'palantir-registry' });
});

// Ensure user exists, return user record
async function ensureUser(robloxUserId, robloxUsername) {
  const existing = await db.query('SELECT * FROM users WHERE roblox_user_id = $1', [robloxUserId]);
  if (existing.rows.length > 0) {
    // Update username if changed
    if (robloxUsername && existing.rows[0].roblox_username !== robloxUsername) {
      await db.query('UPDATE users SET roblox_username = $1 WHERE roblox_user_id = $2', [robloxUsername, robloxUserId]);
    }
    return existing.rows[0];
  }
  const result = await db.query(
    'INSERT INTO users (roblox_user_id, roblox_username) VALUES ($1, $2) RETURNING *',
    [robloxUserId, robloxUsername]
  );
  return result.rows[0];
}

// Register individual mesh(es)
app.post('/register/mesh', async (req, res) => {
  const { robloxUserId, robloxUsername, meshes } = req.body;
  
  if (!robloxUserId || !meshes || !Array.isArray(meshes)) {
    return res.status(400).json({ error: 'Missing robloxUserId or meshes array' });
  }

  try {
    await ensureUser(robloxUserId, robloxUsername);
    
    const registered = [];
    const skipped = [];
    
    for (const mesh of meshes) {
      // Check if already registered
      const existing = await db.query('SELECT owner_id FROM assets WHERE asset_id = $1', [mesh.assetId]);
      
      if (existing.rows.length > 0) {
        if (existing.rows[0].owner_id === robloxUserId) {
          skipped.push({ assetId: mesh.assetId, reason: 'already_owned' });
        } else {
          skipped.push({ assetId: mesh.assetId, reason: 'owned_by_other', owner: existing.rows[0].owner_id });
        }
        continue;
      }
      
      await db.query(
        `INSERT INTO assets (asset_id, owner_id, name, size_x, size_y, size_z, material, texture_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [mesh.assetId, robloxUserId, mesh.name, mesh.sizeX, mesh.sizeY, mesh.sizeZ, mesh.material, mesh.textureId]
      );
      registered.push(mesh.assetId);
    }

    // Discord notification
    if (registered.length > 0) {
      const embed = new EmbedBuilder()
        .setTitle('🔒 Meshes Registered')
        .setColor(0x65d07d)
        .addFields(
          { name: 'User', value: `${robloxUsername} (${robloxUserId})`, inline: true },
          { name: 'Count', value: `${registered.length}`, inline: true }
        )
        .setTimestamp();
      await notifyDiscord(embed);
    }

    res.json({ success: true, registered, skipped });
  } catch (err) {
    console.error('Register mesh error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Register a full model with all its meshes
app.post('/register/model', async (req, res) => {
  const { robloxUserId, robloxUsername, model } = req.body;
  
  if (!robloxUserId || !model || !model.name || !model.meshes) {
    return res.status(400).json({ error: 'Missing robloxUserId or model data' });
  }

  try {
    await ensureUser(robloxUserId, robloxUsername);
    
    // Create model record
    const modelResult = await db.query(
      `INSERT INTO models (owner_id, name, mesh_count, fingerprint)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [robloxUserId, model.name, model.meshes.length, model.fingerprint || null]
    );
    const modelId = modelResult.rows[0].id;
    
    // Insert all mesh references
    const registered = [];
    const skipped = [];
    
    for (const mesh of model.meshes) {
      // Add to model_assets regardless of global registration
      await db.query(
        `INSERT INTO model_assets (model_id, asset_id, name, path, size_x, size_y, size_z, material, texture_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [modelId, mesh.assetId, mesh.name, mesh.path, mesh.sizeX, mesh.sizeY, mesh.sizeZ, mesh.material, mesh.textureId]
      );
      
      // Also register in global assets table if not already owned
      const existing = await db.query('SELECT owner_id FROM assets WHERE asset_id = $1', [mesh.assetId]);
      if (existing.rows.length === 0) {
        await db.query(
          `INSERT INTO assets (asset_id, owner_id, name, size_x, size_y, size_z, material, texture_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
          [mesh.assetId, robloxUserId, mesh.name, mesh.sizeX, mesh.sizeY, mesh.sizeZ, mesh.material, mesh.textureId]
        );
        registered.push(mesh.assetId);
      } else if (existing.rows[0].owner_id !== robloxUserId) {
        skipped.push({ assetId: mesh.assetId, reason: 'owned_by_other', owner: existing.rows[0].owner_id });
      }
    }

    // Discord notification
    const embed = new EmbedBuilder()
      .setTitle('📦 Model Registered')
      .setColor(0x9966ff)
      .addFields(
        { name: 'User', value: `${robloxUsername} (${robloxUserId})`, inline: true },
        { name: 'Model', value: model.name, inline: true },
        { name: 'Meshes', value: `${model.meshes.length} total, ${registered.length} new`, inline: true }
      )
      .setTimestamp();
    await notifyDiscord(embed);

    res.json({ success: true, modelId, registered, skipped });
  } catch (err) {
    console.error('Register model error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Check ownership of asset(s)
app.post('/check', async (req, res) => {
  const { assetIds } = req.body;
  
  if (!assetIds || !Array.isArray(assetIds)) {
    return res.status(400).json({ error: 'Missing assetIds array' });
  }

  try {
    const results = {};
    for (const assetId of assetIds) {
      const result = await db.query(
        `SELECT a.*, u.roblox_username 
         FROM assets a 
         JOIN users u ON a.owner_id = u.roblox_user_id 
         WHERE a.asset_id = $1`,
        [assetId]
      );
      if (result.rows.length > 0) {
        const row = result.rows[0];
        results[assetId] = {
          registered: true,
          ownerId: row.owner_id,
          ownerName: row.roblox_username,
          name: row.name
        };
      } else {
        results[assetId] = { registered: false };
      }
    }
    res.json({ results });
  } catch (err) {
    console.error('Check error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Get user's registered assets
app.get('/user/:robloxUserId', async (req, res) => {
  const { robloxUserId } = req.params;
  
  try {
    const user = await db.query('SELECT * FROM users WHERE roblox_user_id = $1', [robloxUserId]);
    if (user.rows.length === 0) {
      return res.json({ found: false });
    }
    
    const assets = await db.query('SELECT * FROM assets WHERE owner_id = $1 ORDER BY registered_at DESC', [robloxUserId]);
    const models = await db.query('SELECT * FROM models WHERE owner_id = $1 ORDER BY registered_at DESC', [robloxUserId]);
    
    res.json({
      found: true,
      user: user.rows[0],
      assets: assets.rows,
      models: models.rows
    });
  } catch (err) {
    console.error('User lookup error:', err);
    res.status(500).json({ error: err.message });
  }
});

// Log a scan (for tracking/alerts)
app.post('/scan/log', async (req, res) => {
  const { scannerUserId, modelName, assetIds, flaggedAssets } = req.body;
  
  try {
    await db.query(
      `INSERT INTO scan_logs (scanner_user_id, scanned_model_name, asset_ids, flagged_assets)
       VALUES ($1, $2, $3, $4)`,
      [scannerUserId, modelName, assetIds, flaggedAssets]
    );
    
    // Alert if flagged assets found
    if (flaggedAssets && flaggedAssets.length > 0) {
      // Get owner info for flagged assets
      const ownerInfo = await db.query(
        `SELECT DISTINCT a.owner_id, u.roblox_username, u.discord_user_id
         FROM assets a
         JOIN users u ON a.owner_id = u.roblox_user_id
         WHERE a.asset_id = ANY($1)`,
        [flaggedAssets]
      );
      
      const embed = new EmbedBuilder()
        .setTitle('⚠️ Flagged Assets Detected')
        .setColor(0xff6b6b)
        .addFields(
          { name: 'Scanner', value: `${scannerUserId}`, inline: true },
          { name: 'Model Scanned', value: modelName || 'Unknown', inline: true },
          { name: 'Flagged Count', value: `${flaggedAssets.length}`, inline: true },
          { name: 'Original Owners', value: ownerInfo.rows.map(r => `${r.roblox_username} (${r.owner_id})`).join('\n') || 'Unknown' }
        )
        .setTimestamp();
      await notifyDiscord(embed);
    }
    
    res.json({ success: true });
  } catch (err) {
    console.error('Scan log error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============ START SERVER ============
const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`✓ Server running on port ${PORT}`);
});

// Connect Discord bot
if (DISCORD_TOKEN) {
  discord.login(DISCORD_TOKEN).catch(err => {
    console.error('✗ Discord login failed:', err.message);
  });
} else {
  console.log('⚠ No DISCORD_TOKEN, bot disabled');
}
