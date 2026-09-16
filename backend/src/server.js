import {createServer} from 'node:http';
import {WebSocketServer,WebSocket} from 'ws';
import {pool} from './db.js';
import {authenticate} from './auth.js';
import {createApp} from './app.js';
import {startNotifications} from './notifications.js';
import {ensureAdmin} from './admin-bootstrap.js';
// Keep this small compatibility migration automatic for existing Render/Neon
// databases so cancellation fees work immediately after deployment.
await pool.query(`alter table work_charges drop constraint if exists work_charges_amount_check;
  alter table work_charges add constraint work_charges_amount_check check(amount in (-4,-2));`);
if (await ensureAdmin(pool)) {
 console.log('Admin email login configured from environment. Remove ADMIN_PASSWORD after a successful sign-in.');
}
const sockets=new Set();
const broadcast=()=>{for(const ws of sockets)if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify({type:'refresh'}));};
const server=createServer(createApp(pool,broadcast));
const wss=new WebSocketServer({server,path:'/events',maxPayload:1024});
wss.on('connection',ws=>{
 const deadline=setTimeout(()=>ws.close(1008,'Authentication required'),5000);
 ws.once('message',async raw=>{
   try {
     const {token}=JSON.parse(raw.toString());
     if(!await authenticate(pool,token))return ws.close(1008,'Invalid session');
     clearTimeout(deadline);sockets.add(ws);
     ws.send(JSON.stringify({type:'refresh'}));
   }catch(_){ws.close(1008,'Invalid session');}
 });
 ws.on('close',()=>{clearTimeout(deadline);sockets.delete(ws);});
 ws.on('error',()=>sockets.delete(ws));
});
const stopNotifications=startNotifications(pool);
// Cloud hosts such as Render route traffic through the container's public
// interface, so the API must listen on every interface. Local development is
// still limited to the configured port and can override HOST when required.
server.listen(Number(process.env.PORT || 3000),process.env.HOST || '0.0.0.0',()=>console.log('Buklin API listening on port '+(process.env.PORT || 3000)));
process.on('SIGINT',async()=>{stopNotifications();for(const ws of sockets)ws.close();wss.close();server.close();await pool.end();});
