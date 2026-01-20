# Palantir Registry

Asset registration system for the Palantir Roblox Studio plugin.

## Architecture

```
Roblox Plugin → API Server → Neon DB
                    ↓
              Discord Bot
```

## Setup

### 1. Database (Neon)

1. Go to your Neon project dashboard
2. Open the SQL Editor
3. Paste and run the contents of `schema.sql`

### 2. Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Select your bot application
3. Go to **Bot** → Copy the token
4. Go to **OAuth2 → URL Generator**
   - Scopes: `bot`, `applications.commands`
   - Bot Permissions: `Send Messages`, `Embed Links`
5. Use the generated URL to invite the bot to your server
6. Get your server ID: Enable Developer Mode in Discord settings, right-click your server → Copy ID
7. Get your channel ID: Right-click the notification channel → Copy ID

### 3. Deploy to Vercel

1. Push this folder to a GitHub repo
2. Go to [Vercel](https://vercel.com) → New Project → Import your repo
3. Add environment variables in Vercel dashboard:
   - `DATABASE_URL` - Your Neon connection string
   - `DISCORD_TOKEN` - Bot token from step 2
   - `DISCORD_CHANNEL_ID` - Channel for notifications
   - `DISCORD_GUILD_ID` - Your Discord server ID
4. Deploy

### 4. Plugin Integration

1. Copy `lua/Registry.lua` into your Palantir plugin's Modules folder
2. Update `Registry.API_URL` to your Vercel deployment URL
3. Wire up the Registry tab buttons to call the module functions

## API Endpoints

### `POST /register/mesh`
Register individual meshes.
```json
{
  "robloxUserId": 12345678,
  "robloxUsername": "PlayerName",
  "meshes": [
    {
      "assetId": 987654321,
      "name": "Bumper_Front",
      "sizeX": 2.5,
      "sizeY": 1.0,
      "sizeZ": 3.0,
      "material": "SmoothPlastic",
      "textureId": null
    }
  ]
}
```

### `POST /register/model`
Register a complete model with all meshes.
```json
{
  "robloxUserId": 12345678,
  "robloxUsername": "PlayerName",
  "model": {
    "name": "Supra MK4",
    "meshCount": 47,
    "fingerprint": "abc123",
    "meshes": [...]
  }
}
```

### `POST /check`
Check ownership of asset IDs.
```json
{
  "assetIds": [123456, 789012, 345678]
}
```

Response:
```json
{
  "results": {
    "123456": { "registered": true, "ownerId": 12345678, "ownerName": "PlayerName" },
    "789012": { "registered": false },
    "345678": { "registered": true, "ownerId": 99999999, "ownerName": "OtherPlayer" }
  }
}
```

### `GET /user/:robloxUserId`
Get all assets registered to a user.

### `POST /scan/log`
Log a scan and trigger alerts for flagged assets.

## Discord Commands

- `/lookup <asset_id>` - Check who owns an asset
- `/user <roblox_id>` - View a user's registered assets
- `/stats` - View registry statistics

## Local Development

```bash
cp .env.example .env
# Fill in your values
npm install
npm run dev
```
