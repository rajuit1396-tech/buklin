import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import request from 'supertest';
import {createApp} from '../src/app.js';
import {hashPassword,checkPassword} from '../src/auth.js';

test('only admins reset customer/operator passwords and revoke all target sessions',async()=>{
  const db=new PGlite();
  await db.exec(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
  let tail=Promise.resolve();
  async function lock(){let unlock;const previous=tail;tail=new Promise(r=>unlock=r);await previous;return unlock;}
  const run=async(sql,args)=>{const r=await db.query(sql,args);return {...r,rowCount:Math.max(r.affectedRows??0,r.rows.length)};};
  const pool={query:async(sql,args)=>{const done=await lock();try{return await run(sql,args);}finally{done();}},
    connect:async()=>{const done=await lock();return {query:run,release:done};}};
  const api=request(createApp(pool,()=>{},{testing:true}));
  const oldPassword='OriginalPassword123',newPassword='New password 456!';
  const login=(email,password=oldPassword)=>api.post('/auth/login').send({email,password});
  const reset=(id,token,password=newPassword)=>api.post(`/admin/users/${id}/password`).auth(token,{type:'bearer'}).send({password});
  try{
    const users={};
    for(const role of ['admin','customer','operator']){
      const id=randomUUID(),email=role+'@example.com';
      await pool.query('insert into users(id,email,role,service,password_hash) values($1,$2,$3,$4,$5)',
        [id,email,role,role==='operator'?'Pickup van':null,await hashPassword(oldPassword)]);
      const result=await login(email);assert.equal(result.status,200);
      users[role]={id,email,token:result.body.token};
    }
    const {admin,customer,operator}=users;
    assert.equal((await api.post(`/admin/users/${customer.id}/password`).send({password:newPassword})).status,401);
    for(const actor of [customer,operator]){
      assert.equal((await reset(customer.id,actor.token)).status,403);
      assert.equal((await reset(operator.id,actor.token)).status,403);
    }
    for(const password of [undefined,null,123,'short','a'.repeat(129)])
      assert.equal((await reset(customer.id,admin.token,password===undefined?null:password)).status,400);
    assert.equal((await reset('bad-id',admin.token)).status,400);
    assert.equal((await reset(randomUUID(),admin.token)).status,404);
    assert.equal((await reset(admin.id,admin.token)).status,404);
    const deleted=randomUUID();
    await pool.query("insert into users(id,email,password_hash,deleted_at) values($1,'deleted@example.com',$2,now())",[deleted,await hashPassword(oldPassword)]);
    assert.equal((await reset(deleted,admin.token)).status,404);
    assert.equal((await login(customer.email)).status,200);
    for(const target of [customer,operator]){
      const second=await login(target.email);assert.equal(second.status,200);
      const result=await reset(target.id,admin.token);
      assert.equal(result.status,200);assert.deepEqual(result.body,{ok:true});
      for(const token of [target.token,second.body.token])
        assert.equal((await api.get('/me').auth(token,{type:'bearer'})).status,401);
      assert.equal((await login(target.email)).status,401);
      assert.equal((await login(target.email,newPassword)).status,200);
      const stored=(await pool.query('select password_hash from users where id=$1',[target.id])).rows[0].password_hash;
      assert.notEqual(stored,newPassword);assert.equal(await checkPassword(newPassword,stored),true);
      const audit=(await pool.query("select description from activity_log where user_id=$1 and description like 'Password changed%'",[target.id])).rows;
      assert.equal(audit.length,1);assert.ok(audit[0].description.includes(admin.id));
      assert.ok(!audit[0].description.includes(newPassword));
    }
    assert.equal((await api.get('/me').auth(admin.token,{type:'bearer'})).status,200);
  }finally{await db.close();}
});
