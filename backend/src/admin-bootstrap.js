import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {hashPassword} from './auth.js';

export async function ensureAdmin(pool) {
  if (!process.env.ADMIN_EMAIL || !process.env.ADMIN_PASSWORD) return false;
  const email=z.email().parse(process.env.ADMIN_EMAIL.trim().toLowerCase());
  const password=z.string().min(10).max(128).parse(process.env.ADMIN_PASSWORD);
  const hash=await hashPassword(password);
  const result=await pool.query(`insert into users(id,name,email,password_hash,role)
    values($1,$2,$3,$4,'admin') on conflict(email) do update set
    name=excluded.name,password_hash=excluded.password_hash
    where users.role='admin' returning id`,
    [randomUUID(),process.env.ADMIN_NAME || 'Buklin Admin',email,hash]);
  if(!result.rowCount) throw new Error('ADMIN_EMAIL belongs to a non-admin account; admin login was not changed.');
  return true;
}
