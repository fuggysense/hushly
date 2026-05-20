const fs = require('node:fs/promises');
const path = require('node:path');
const { Client } = require('pg');

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('DATABASE_URL not set');

  const client = new Client({
    connectionString,
    ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  await client.connect();
  try {
    await client.query(`
      create table if not exists schema_migrations (
        version text primary key,
        applied_at timestamptz not null default now()
      )
    `);
    const dir = path.join(__dirname, '../db/migrations');
    const files = (await fs.readdir(dir)).filter((file) => file.endsWith('.sql')).sort();
    for (const file of files) {
      const existing = await client.query('select 1 from schema_migrations where version = $1', [
        file,
      ]);
      if (existing.rowCount) {
        console.log(`skip ${file}`);
        continue;
      }
      const sql = await fs.readFile(path.join(dir, file), 'utf8');
      await client.query('begin');
      try {
        await client.query(sql);
        await client.query('insert into schema_migrations (version) values ($1)', [file]);
        await client.query('commit');
        console.log(`applied ${file}`);
      } catch (error) {
        await client.query('rollback');
        throw error;
      }
    }
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
