import 'dotenv/config';
import crypto from 'crypto';
import express from 'express';
import cors from 'cors';
import { Client, GatewayIntentBits, EmbedBuilder, REST, Routes, SlashCommandBuilder } from 'discord.js';
import db from './db.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const DISCORD_CHANNEL_ID = process.env.DISCORD_CHANNEL_ID;
const DISCORD_GUILD_ID = process.env.DISCORD_GUILD_ID;

const discord = new Client({
  intents: [GatewayIntentBits.Guilds]
});

let botReady = false;

function buildOwnerKey() {
  return crypto.randomBytes(24).toString('hex');
}

function getOwnerKey(req) {
  return (
    req.body?.owner_key ||
    req.body?.ownerKey ||
    req.query?.owner_key ||
    req.query?.ownerKey ||
    req.headers['x-owner-key']
  );
}

async function requireOwner(req, res) {
  const ownerKey = getOwnerKey(req);
  if (!ownerKey) {
    res.status(401).json({ error: 'Missing owner_key' });
    return null;
  }

  const result = await db.query('SELECT * FROM owners WHERE owner_key = $1', [ownerKey]);
  if (result.rows.length === 0) {
    res.status(401).json({ error: 'Invalid owner_key' });
    return null;
  }

  return result.rows[0];
}

async function requireModelOwner(req, res, modelId) {
  const owner = await requireOwner(req, res);
  if (!owner) return null;

  const modelResult = await db.query('SELECT * FROM models WHERE id = $1 AND owner_id = $2', [modelId, owner.id]);
  if (modelResult.rows.length === 0) {
    res.status(404).json({ error: 'Model not found for owner' });
    return null;
  }

  return { owner, model: modelResult.rows[0] };
}

async function notifyDiscord(embed) {
  if (!botReady || !DISCORD_CHANNEL_ID) return;
  try {
    const channel = await discord.channels.fetch(DISCORD_CHANNEL_ID);
    if (channel) await channel.send({ embeds: [embed] });
  } catch (err) {
    console.error('Discord notification failed:', err.message);
  }
}

// ============ DISCORD BOT SETUP ============
if (DISCORD_TOKEN) {
  discord.once('ready', async () => {
    console.log(`Discord bot logged in as ${discord.user.tag}`);
    botReady = true;

    if (!DISCORD_GUILD_ID) {
      console.warn('Missing DISCORD_GUILD_ID, slash commands not registered.');
      return;
    }

    const commands = [
      new SlashCommandBuilder()
        .setName('lookup')
        .setDescription('Look up a model by ID')
        .addStringOption(opt =>
          opt.setName('model_id')
            .setDescription('The model ID to look up')
            .setRequired(true)),
      new SlashCommandBuilder()
        .setName('stats')
        .setDescription('View registry statistics')
        .addStringOption(opt =>
          opt.setName('model_id')
            .setDescription('Optional model ID for per-model stats')
            .setRequired(false)),
      new SlashCommandBuilder()
        .setName('whitelist')
        .setDescription('Show whitelisted users for a model')
        .addStringOption(opt =>
          opt.setName('model_id')
            .setDescription('The model ID to list')
            .setRequired(true))
    ].map(cmd => cmd.toJSON());

    const rest = new REST({ version: '10' }).setToken(DISCORD_TOKEN);
    try {
      await rest.put(Routes.applicationGuildCommands(discord.user.id, DISCORD_GUILD_ID), { body: commands });
      console.log('Slash commands registered');
    } catch (err) {
      console.error('Failed to register slash commands:', err.message);
    }
  });

  discord.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    if (interaction.commandName === 'lookup') {
      const modelId = interaction.options.getString('model_id');
      try {
        const result = await db.query(
          `SELECT m.*, o.display_name AS owner_name
           FROM models m
           JOIN owners o ON m.owner_id = o.id
           WHERE m.id = $1`,
          [modelId]
        );

        if (result.rows.length === 0) {
          await interaction.reply({ content: `Model \`${modelId}\` not found.`, ephemeral: true });
          return;
        }

        const model = result.rows[0];
        const embed = new EmbedBuilder()
          .setTitle('Model Lookup')
          .setColor(0x2f855a)
          .addFields(
            { name: 'Model ID', value: modelId, inline: true },
            { name: 'Name', value: model.display_name || 'Unknown', inline: true },
            { name: 'Owner', value: model.owner_name || 'Unknown', inline: false },
            { name: 'Meshes', value: String(model.mesh_count || 0), inline: true },
            { name: 'Registered', value: new Date(model.registered_at).toLocaleDateString(), inline: true }
          );

        await interaction.reply({ embeds: [embed] });
      } catch (err) {
        await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
      }
    }

    if (interaction.commandName === 'stats') {
      const modelId = interaction.options.getString('model_id');
      try {
        if (modelId) {
          const stats = await db.query(
            `SELECT
              (SELECT COUNT(*) FROM whitelist WHERE model_id = $1) AS whitelist_count,
              (SELECT COUNT(*) FROM usage_logs WHERE model_id = $1) AS usage_count,
              (SELECT mesh_count FROM models WHERE id = $1) AS mesh_count`,
            [modelId]
          );

          const row = stats.rows[0];
          const embed = new EmbedBuilder()
            .setTitle('Model Stats')
            .setColor(0x3182ce)
            .addFields(
              { name: 'Model ID', value: modelId, inline: false },
              { name: 'Listings', value: String(row.mesh_count || 0), inline: true },
              { name: 'Whitelist', value: String(row.whitelist_count || 0), inline: true },
              { name: 'Usages', value: String(row.usage_count || 0), inline: true }
            );

          await interaction.reply({ embeds: [embed] });
        } else {
          const totals = await db.query(
            `SELECT
              (SELECT COUNT(*) FROM owners) AS owners,
              (SELECT COUNT(*) FROM models) AS models,
              (SELECT COUNT(*) FROM whitelist) AS whitelist,
              (SELECT COUNT(*) FROM usage_logs) AS usages`
          );

          const row = totals.rows[0];
          const embed = new EmbedBuilder()
            .setTitle('Registry Stats')
            .setColor(0x3182ce)
            .addFields(
              { name: 'Owners', value: String(row.owners), inline: true },
              { name: 'Models', value: String(row.models), inline: true },
              { name: 'Whitelist', value: String(row.whitelist), inline: true },
              { name: 'Usages', value: String(row.usages), inline: true }
            );

          await interaction.reply({ embeds: [embed] });
        }
      } catch (err) {
        await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
      }
    }

    if (interaction.commandName === 'whitelist') {
      const modelId = interaction.options.getString('model_id');
      try {
        const result = await db.query(
          `SELECT user_id, note, added_at
           FROM whitelist
           WHERE model_id = $1
           ORDER BY added_at DESC`,
          [modelId]
        );

        if (result.rows.length === 0) {
          await interaction.reply({ content: `No whitelisted users for \`${modelId}\`.`, ephemeral: true });
          return;
        }

        const preview = result.rows.slice(0, 20).map(row => {
          const note = row.note ? ` - ${row.note}` : '';
          return `${row.user_id}${note}`;
        }).join('\n');

        const extra = result.rows.length > 20 ? `\n...and ${result.rows.length - 20} more` : '';

        const embed = new EmbedBuilder()
          .setTitle('Whitelist')
          .setColor(0xd69e2e)
          .addFields(
            { name: 'Model ID', value: modelId, inline: false },
            { name: 'Count', value: String(result.rows.length), inline: true },
            { name: 'Users', value: `${preview}${extra}`, inline: false }
          );

        await interaction.reply({ embeds: [embed] });
      } catch (err) {
        await interaction.reply({ content: `Error: ${err.message}`, ephemeral: true });
      }
    }
  });

  discord.login(DISCORD_TOKEN).catch(err => {
    console.error('Discord login failed:', err.message);
  });
} else {
  console.log('No DISCORD_TOKEN, bot disabled');
}

// ============ API ROUTES ============

app.get('/', (req, res) => {
  res.json({ status: 'ok', service: 'palantir-registry' });
});

app.post('/owner/create', async (req, res) => {
  const { display_name, roblox_user_id, roblox_group_id, discord_user_id } = req.body || {};

  try {
    const ownerKey = buildOwnerKey();
    const result = await db.query(
      `INSERT INTO owners (display_name, owner_key, roblox_user_id, roblox_group_id, discord_user_id)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [display_name || null, ownerKey, roblox_user_id || null, roblox_group_id || null, discord_user_id || null]
    );

    res.json({ owner: result.rows[0], owner_key: ownerKey });
  } catch (err) {
    console.error('Owner create error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/owner/rotate-key', async (req, res) => {
  const owner = await requireOwner(req, res);
  if (!owner) return;

  try {
    const newKey = buildOwnerKey();
    const result = await db.query(
      'UPDATE owners SET owner_key = $1 WHERE id = $2 RETURNING *',
      [newKey, owner.id]
    );

    res.json({ owner: result.rows[0], owner_key: newKey });
  } catch (err) {
    console.error('Owner rotate key error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/model/register', async (req, res) => {
  const owner = await requireOwner(req, res);
  if (!owner) return;

  const { display_name, roblox_asset_id, mesh_count, fingerprint } = req.body || {};
  if (!display_name) {
    return res.status(400).json({ error: 'Missing display_name' });
  }

  try {
    const result = await db.query(
      `INSERT INTO models (owner_id, display_name, roblox_asset_id, mesh_count, fingerprint)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [owner.id, display_name, roblox_asset_id || null, mesh_count || 0, fingerprint || null]
    );

    const model = result.rows[0];

    const embed = new EmbedBuilder()
      .setTitle('Model Registered')
      .setColor(0x805ad5)
      .addFields(
        { name: 'Owner', value: owner.display_name || String(owner.id), inline: true },
        { name: 'Model', value: model.display_name, inline: true },
        { name: 'Model ID', value: model.id, inline: false }
      )
      .setTimestamp();

    await notifyDiscord(embed);

    res.json({ model });
  } catch (err) {
    console.error('Model register error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/model/:modelId', async (req, res) => {
  const { modelId } = req.params;
  const ownerKey = req.query?.owner_key;

  try {
    const result = await db.query(
      `SELECT m.*, o.display_name AS owner_name, o.id AS owner_db_id
       FROM models m
       JOIN owners o ON m.owner_id = o.id
       WHERE m.id = $1 AND o.owner_key = $2`,
      [modelId, ownerKey]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Model not found or access denied' });
    }

    res.json({ model: result.rows[0] });
  } catch (err) {
    console.error('Model fetch error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/whitelist/add', async (req, res) => {
  const { model_id, user_id, note } = req.body || {};
  if (!model_id || !user_id) {
    return res.status(400).json({ error: 'Missing model_id or user_id' });
  }

  const auth = await requireModelOwner(req, res, model_id);
  if (!auth) return;

  try {
    const result = await db.query(
      `INSERT INTO whitelist (model_id, user_id, note)
       VALUES ($1, $2, $3)
       ON CONFLICT (model_id, user_id) DO UPDATE SET note = EXCLUDED.note
       RETURNING *`,
      [model_id, user_id, note || null]
    );

    res.json({ entry: result.rows[0] });
  } catch (err) {
    console.error('Whitelist add error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/whitelist/add-many', async (req, res) => {
  const { model_id, user_ids, note } = req.body || {};
  if (!model_id || !Array.isArray(user_ids)) {
    return res.status(400).json({ error: 'Missing model_id or user_ids array' });
  }

  const auth = await requireModelOwner(req, res, model_id);
  if (!auth) return;

  const chunkSize = 100;
  let inserted = 0;

  try {
    for (let i = 0; i < user_ids.length; i += chunkSize) {
      const chunk = user_ids.slice(i, i + chunkSize);
      const values = [];
      const params = [];

      chunk.forEach((userId, index) => {
        const base = index * 3;
        values.push(`($${base + 1}, $${base + 2}, $${base + 3})`);
        params.push(model_id, userId, note || null);
      });

      const query = `
        INSERT INTO whitelist (model_id, user_id, note)
        VALUES ${values.join(', ')}
        ON CONFLICT (model_id, user_id) DO UPDATE SET note = EXCLUDED.note`;

      await db.query(query, params);
      inserted += chunk.length;
    }

    res.json({ inserted });
  } catch (err) {
    console.error('Whitelist add-many error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/whitelist/remove', async (req, res) => {
  const { model_id, user_id } = req.body || {};
  if (!model_id || !user_id) {
    return res.status(400).json({ error: 'Missing model_id or user_id' });
  }

  const auth = await requireModelOwner(req, res, model_id);
  if (!auth) return;

  try {
    const result = await db.query(
      'DELETE FROM whitelist WHERE model_id = $1 AND user_id = $2',
      [model_id, user_id]
    );

    res.json({ removed: result.rowCount });
  } catch (err) {
    console.error('Whitelist remove error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/whitelist/:modelId', async (req, res) => {
  const { modelId } = req.params;
  const auth = await requireModelOwner(req, res, modelId);
  if (!auth) return;

  try {
    const result = await db.query(
      `SELECT user_id, note, added_at
       FROM whitelist
       WHERE model_id = $1
       ORDER BY added_at DESC`,
      [modelId]
    );

    res.json({ count: result.rows.length, users: result.rows });
  } catch (err) {
    console.error('Whitelist list error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/meshes/upsert', async (req, res) => {
  const { model_id, meshes } = req.body || {};
  if (!model_id || !Array.isArray(meshes)) {
    return res.status(400).json({ error: 'Missing model_id or meshes array' });
  }

  const auth = await requireModelOwner(req, res, model_id);
  if (!auth) return;

  const chunkSize = 200;
  let upserted = 0;

  try {
    for (let i = 0; i < meshes.length; i += chunkSize) {
      const chunk = meshes.slice(i, i + chunkSize);
      const values = [];
      const params = [];

      chunk.forEach((mesh, index) => {
        const assetId = mesh.mesh_asset_id ?? mesh.assetId ?? mesh.asset_id;
        const name = mesh.mesh_name ?? mesh.name ?? null;
        const base = index * 3;
        values.push(`($${base + 1}, $${base + 2}, $${base + 3})`);
        params.push(model_id, assetId, name);
      });

      const query = `
        INSERT INTO model_meshes (model_id, mesh_asset_id, mesh_name)
        VALUES ${values.join(', ')}
        ON CONFLICT (model_id, mesh_asset_id)
        DO UPDATE SET mesh_name = EXCLUDED.mesh_name`;

      await db.query(query, params);
      upserted += chunk.length;
    }

    const countResult = await db.query(
      'SELECT COUNT(*)::int AS count FROM model_meshes WHERE model_id = $1',
      [model_id]
    );

    await db.query('UPDATE models SET mesh_count = $1 WHERE id = $2', [countResult.rows[0].count, model_id]);

    res.json({ upserted, mesh_count: countResult.rows[0].count });
  } catch (err) {
    console.error('Meshes upsert error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/access/check', async (req, res) => {
  const { model_id, actor_user_id, place_id, server_job_id, mesh_ids, meta } = req.body || {};

  if (!model_id || !actor_user_id) {
    return res.status(400).json({ error: 'Missing model_id or actor_user_id' });
  }

  try {
    const modelResult = await db.query(
      `SELECT m.*, o.roblox_user_id AS owner_roblox_user_id
       FROM models m
       JOIN owners o ON m.owner_id = o.id
       WHERE m.id = $1`,
      [model_id]
    );

    if (modelResult.rows.length === 0) {
      return res.status(404).json({ error: 'Model not found' });
    }

    const model = modelResult.rows[0];

    let allowed = false;
    let reason = 'not_whitelisted';

    if (model.owner_roblox_user_id && String(model.owner_roblox_user_id) === String(actor_user_id)) {
      allowed = true;
      reason = 'owner';
    } else {
      const whitelist = await db.query(
        'SELECT 1 FROM whitelist WHERE model_id = $1 AND user_id = $2',
        [model_id, actor_user_id]
      );

      if (whitelist.rows.length > 0) {
        allowed = true;
        reason = 'whitelisted';
      }
    }

    await db.query(
      `INSERT INTO usage_logs (model_id, actor_user_id, place_id, server_job_id, mesh_ids, meta, allowed, reason)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        model_id,
        actor_user_id,
        place_id || null,
        server_job_id || null,
        Array.isArray(mesh_ids) ? mesh_ids : null,
        meta || null,
        allowed,
        reason
      ]
    );

    if (!allowed) {
      const embed = new EmbedBuilder()
        .setTitle('Unauthorized Model Access')
        .setColor(0xe53e3e)
        .addFields(
          { name: 'Model ID', value: model_id, inline: true },
          { name: 'Actor', value: String(actor_user_id), inline: true },
          { name: 'Reason', value: reason, inline: true }
        )
        .setTimestamp();

      await notifyDiscord(embed);
    }

    res.json({ allowed, reason });
  } catch (err) {
    console.error('Access check error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/usage-logs/:modelId', async (req, res) => {
  const { modelId } = req.params;
  const auth = await requireModelOwner(req, res, modelId);
  if (!auth) return;

  const page = Math.max(parseInt(req.query.page || '1', 10), 1);
  const pageSize = Math.min(Math.max(parseInt(req.query.page_size || '50', 10), 1), 200);
  const offset = (page - 1) * pageSize;

  try {
    const totalResult = await db.query(
      'SELECT COUNT(*)::int AS count FROM usage_logs WHERE model_id = $1',
      [modelId]
    );

    const logsResult = await db.query(
      `SELECT * FROM usage_logs
       WHERE model_id = $1
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [modelId, pageSize, offset]
    );

    res.json({
      page,
      page_size: pageSize,
      total: totalResult.rows[0].count,
      logs: logsResult.rows
    });
  } catch (err) {
    console.error('Usage logs error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/stats/:modelId', async (req, res) => {
  const { modelId } = req.params;
  const auth = await requireModelOwner(req, res, modelId);
  if (!auth) return;

  try {
    const stats = await db.query(
      `SELECT
        (SELECT COUNT(*) FROM whitelist WHERE model_id = $1) AS whitelist_count,
        (SELECT COUNT(*) FROM usage_logs WHERE model_id = $1) AS usage_count,
        (SELECT COUNT(*) FROM model_meshes WHERE model_id = $1) AS mesh_count`,
      [modelId]
    );

    const row = stats.rows[0];
    res.json({
      model_id: modelId,
      listings: parseInt(row.mesh_count, 10),
      whitelist_count: parseInt(row.whitelist_count, 10),
      usage_count: parseInt(row.usage_count, 10)
    });
  } catch (err) {
    console.error('Stats error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============ START SERVER ============
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
