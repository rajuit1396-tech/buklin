import {pool} from './db.js';
const [email,service] = process.argv.slice(2);
if (!email || !['5-finger excavator grapple','Pickup van','Big truck'].includes(service)) {
 console.error('Usage: npm run operator -- email "Pickup van"'); process.exit(1);
}
try {
 const result = await pool.query('update users set role=$1,service=$2 where email=$3',['operator',service,email.toLowerCase()]);
 if (!result.rowCount) throw new Error('Account not found; register first');
 console.log('Operator approved. Sign in again.');
} finally { await pool.end(); }
