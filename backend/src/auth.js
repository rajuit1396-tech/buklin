import { randomBytes, scrypt, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
const derive = promisify(scrypt);
export const tokenHash = value => createHash('sha256').update(value).digest('hex');
export async function hashPassword(password) {
 const salt = randomBytes(16).toString('hex');
 return `${salt}:${(await derive(password,salt,64)).toString('hex')}`;
}
export async function checkPassword(password, encoded) {
 const [salt, hash] = encoded.split(':');
 const actual = await derive(password,salt,64);
 return timingSafeEqual(actual,Buffer.from(hash,'hex'));
}
export async function authenticate(pool, token) {
 if (!token || token.length > 200) return null;
 const {rows} = await pool.query(`select u.id,u.email,u.name,u.phone,u.username,u.role,u.service,u.store_number,u.site_lat,u.site_lng,u.site_address,u.online,u.blocked_until from sessions s
 join users u on u.id=s.user_id where s.token_hash=$1 and s.expires_at>now() and u.deleted_at is null`,[tokenHash(token)]);
 return rows[0] ?? null;
}
