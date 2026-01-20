import pg from 'pg';
const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

// Test connection on startup
pool.query('SELECT NOW()')
  .then(() => console.log('✓ Database connected'))
  .catch(err => console.error('✗ Database connection failed:', err.message));

export default pool;
