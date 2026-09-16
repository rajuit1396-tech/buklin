import {createServer} from 'node:http';
import {WebSocketServer,WebSocket} from 'ws';
import {pool} from './db.js';
import {authenticate} from './auth.js';
import {createApp} from './app.js';
import {startNotifications} from './notifications.js';
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
server.listen(Number(process.env.PORT || 3000),process.env.HOST || '127.0.0.1',()=>console.log('Buklin API listening on port '+(process.env.PORT || 3000)));
process.on('SIGINT',async()=>{stopNotifications();for(const ws of sockets)ws.close();wss.close();server.close();await pool.end();});
