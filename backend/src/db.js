import pg from 'pg';
if (!process.env.DATABASE_URL) throw new Error('Set DATABASE_URL in backend/.env to your Neon connection string');
export const pool = new pg.Pool({connectionString:process.env.DATABASE_URL,max:10,connectionTimeoutMillis:10000});
