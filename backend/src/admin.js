import {randomUUID} from 'node:crypto';
import {pool} from './db.js';
import {hashPassword} from './auth.js';
import {accountFields} from './account-validation.js';
import {z} from 'zod';
try {
  if (process.env.ADMIN_EMAIL) {
    const email=z.email().parse(process.env.ADMIN_EMAIL.trim().toLowerCase());
    const password=z.string().min(10).max(128).parse(process.env.ADMIN_PASSWORD);
    const hash=await hashPassword(password);
    const result=await pool.query(`insert into users(id,name,email,password_hash,role)
      values($1,$2,$3,$4,'admin') on conflict(email) do update set password_hash=excluded.password_hash
      where users.role='admin' returning id`,[randomUUID(),process.env.ADMIN_NAME || 'Admin',email,hash]);
    if(!result.rowCount) throw new Error('This email belongs to a non-admin account; no changes made.');
    console.log('Admin email login configured. Remove ADMIN_PASSWORD from .env after use.');
  } else {
  const parsed=accountFields.safeParse({name:process.env.ADMIN_NAME,phone:process.env.ADMIN_PHONE,
    username:process.env.ADMIN_USERNAME,password:process.env.ADMIN_PASSWORD});
  if(!parsed.success) throw new Error('Set valid ADMIN_NAME, ADMIN_PHONE, ADMIN_USERNAME and ADMIN_PASSWORD in backend/.env. Password must be at least 10 characters.');
  const account=parsed.data;
  await pool.query(`insert into users(id,name,phone,username,password_hash,role)
    values($1,$2,$3,$4,$5,'admin')`,[randomUUID(),account.name,account.phone,account.username,await hashPassword(account.password)]);
  console.log('Admin created. Sign in with the configured username. Remove ADMIN_PASSWORD from .env after use.');
  }
} catch(error) {
  console.error(error.code==='23505'?'Username already exists; no changes made.':error.message);
  process.exitCode=1;
} finally {await pool.end();}
