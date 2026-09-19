const byId=id=>document.getElementById(id);
const loginView=byId('loginView'),panelView=byId('panelView'),message=byId('message');
let token=sessionStorage.getItem('buklinAdminToken')||'';
let messageTimer;

function notice(text,error=false){
  clearTimeout(messageTimer);message.textContent=text;message.className=`message show ${error?'error':'success'}`;
  messageTimer=setTimeout(()=>message.className='message',5000);
}
function showLogin(){token='';sessionStorage.removeItem('buklinAdminToken');sessionStorage.removeItem('buklinAdminUser');loginView.hidden=false;panelView.hidden=true;byId('logoutButton').hidden=true;}
function showPanel(user){loginView.hidden=true;panelView.hidden=false;byId('logoutButton').hidden=false;byId('adminName').textContent=`Signed in as ${user.name||user.email||user.username}`;}
async function api(path,options={}){
  const headers={...(options.body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:`Bearer ${token}`}:{})};
  const response=await fetch(path,{...options,headers:{...headers,...options.headers}});
  let data={};try{data=await response.json();}catch{data={error:'The server returned an invalid response'};}
  if(!response.ok){if(response.status===401&&token)showLogin();throw new Error(data.error||`Request failed (${response.status})`);}return data;
}
function stat(label,value){const box=document.createElement('div');box.className='stat';const number=document.createElement('b');number.textContent=value??0;const text=document.createElement('span');text.textContent=label;box.append(number,text);return box;}
function accountRow(user){
  const row=document.createElement('article');row.className='account';const info=document.createElement('div');const title=document.createElement('h3');title.textContent=user.name+(user.deleted_at?' (Archived)':'');
  const identity=document.createElement('p');identity.textContent=`@${user.username} · ${user.phone}`;const detail=document.createElement('p');detail.textContent=user.role==='operator'?`Operator · ${user.service}`:'Customer';
  const balance=document.createElement('p');balance.className='balance';balance.textContent=`Balance: ${user.balance??0}`;info.append(title,identity,detail,balance);
  if(user.blocked_until){const blocked=document.createElement('p');blocked.textContent=`Restricted until ${new Date(user.blocked_until).toLocaleString()}`;info.append(blocked);}
  const actions=document.createElement('div');actions.className='actions';
  const history=actionButton('Work history',()=>showJobs(user));actions.append(history);
  if(!user.deleted_at){const payment=actionButton('Add payment',()=>adjustBalance(user,'payment'));const adjust=actionButton('Adjust',()=>adjustBalance(user,'adjustment'));const set=actionButton('Set balance',()=>setBalance(user));actions.prepend(payment,adjust,set);
    if(user.blocked_until){const clear=document.createElement('button');clear.type='button';clear.className='ghost';clear.textContent='Clear restriction';clear.addEventListener('click',()=>clearRestriction(user));actions.append(clear);}
    const remove=actionButton('Delete account',()=>deleteAccount(user));remove.classList.add('danger');actions.append(remove);}
  row.append(info,actions);return row;
}
function actionButton(label,handler){const button=document.createElement('button');button.type='button';button.className='ghost';button.textContent=label;button.addEventListener('click',handler);return button;}
async function refresh(){
  try{const search=byId('searchInput').value.trim();const [dashboard,accounts]=await Promise.all([api('/admin/dashboard'),api(`/admin/users?search=${encodeURIComponent(search)}`)]);
    const totals=byId('totals');totals.replaceChildren(stat('Customers',dashboard.totals.customers),stat('Operators',dashboard.totals.operators),stat('Operators online',dashboard.totals.online_operators),stat('Customer requests',dashboard.totals.total_requests),stat('Waiting requests',dashboard.totals.waiting_requests),stat('Active jobs',dashboard.totals.active_jobs),stat('Completed work',dashboard.totals.completed_jobs),stat('Work fees',dashboard.totals.fees),stat('Payments received',dashboard.totals.received),stat('Amount owed',dashboard.totals.owed),stat('Account credit',dashboard.totals.credit));
    const list=byId('accounts');list.replaceChildren(...accounts.users.map(accountRow));if(!accounts.users.length){const empty=document.createElement('p');empty.textContent='No accounts found.';list.append(empty);}
  }catch(error){notice(error.message,true);}
}
async function adjustBalance(user,kind){
  const raw=prompt(kind==='payment'?`Enter payment received from ${user.name}:`:`Enter an adjustment for ${user.name}. Positive adds credit; negative adds debt.`);if(raw===null)return;const amount=Number(raw);if(!Number.isInteger(amount)||amount===0||(kind==='payment'&&amount<1)){notice(kind==='payment'?'Enter a positive whole number.':'Enter a non-zero whole number.',true);return;}
  const reason=prompt(kind==='payment'?'Payment note:':'Reason for this adjustment:');if(reason===null)return;
  try{await api(`/admin/users/${user.id}/balance`,{method:'POST',body:JSON.stringify({id:crypto.randomUUID(),amount,reason,kind})});notice('Balance updated.');await refresh();}catch(error){notice(error.message,true);}
}
async function setBalance(user){const raw=prompt(`Set the exact balance for ${user.name}:`,String(user.balance??0));if(raw===null)return;const balance=Number(raw);if(!Number.isInteger(balance)){notice('Enter a whole-number balance.',true);return;}const reason=prompt('Reason for setting this balance:');if(reason===null)return;try{await api(`/admin/users/${user.id}/balance/set`,{method:'POST',body:JSON.stringify({id:crypto.randomUUID(),balance,reason})});notice(`Balance set to ${balance}.`);await refresh();}catch(error){notice(error.message,true);}}
async function showJobs(user){try{const data=await api(`/admin/users/${user.id}/jobs`);const lines=data.jobs.slice(0,12).map(job=>`#BK-${job.request_number ?? job.id} · ${new Date(job.created_at).toLocaleDateString()} · ${job.service} · ${job.status} · ${job.participation}`);alert(`${user.name}\nCompleted: ${data.completed}\nTotal work records: ${data.total}\n\n${lines.join('\n')||'No work history'}`);}catch(error){notice(error.message,true);}}
async function deleteAccount(user){if(!confirm(`Delete ${user.name}'s ${user.role} account? Any unfinished request will be cancelled and the user will be signed out.`))return;try{await api(`/admin/users/${user.id}`,{method:'DELETE'});notice('Account deleted.');await refresh();}catch(error){notice(error.message,true);}}
async function clearRestriction(user){try{await api(`/admin/users/${user.id}/clear-restriction`,{method:'POST'});notice('Restriction cleared.');await refresh();}catch(error){notice(error.message,true);}}
byId('loginForm').addEventListener('submit',async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;try{const values=new FormData(event.currentTarget);const data=await api('/auth/login',{method:'POST',body:JSON.stringify({email:values.get('email').trim(),password:values.get('password'),admin_only:true})});token=data.token;sessionStorage.setItem('buklinAdminToken',token);sessionStorage.setItem('buklinAdminUser',JSON.stringify(data.user));showPanel(data.user);event.currentTarget.reset();await refresh();}catch(error){notice(error.message,true);}finally{button.disabled=false;}});
byId('accountForm').addEventListener('submit',async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;try{const values=new FormData(event.currentTarget);const role=values.get('role');await api('/admin/users',{method:'POST',body:JSON.stringify({name:values.get('name'),phone:values.get('phone'),username:values.get('username'),password:values.get('password'),role,service:role==='operator'?values.get('service'):null})});notice('Account created.');event.currentTarget.reset();byId('roleSelect').dispatchEvent(new Event('change'));await refresh();}catch(error){notice(error.message,true);}finally{button.disabled=false;}});
function syncAccountType(){const isOperator=byId('roleSelect').value==='operator';byId('serviceField').hidden=!isOperator;byId('serviceSelect').disabled=!isOperator;byId('serviceSelect').required=isOperator;}
function setPasswordVisible(visible){byId('accountPassword').type=visible?'text':'password';byId('showPasswordButton').textContent=visible?'Hide password':'Show password';byId('showPasswordButton').setAttribute('aria-pressed',String(visible));}
byId('showPasswordButton').addEventListener('click',()=>setPasswordVisible(byId('accountPassword').type==='password'));
byId('accountForm').addEventListener('reset',()=>setPasswordVisible(false));
byId('roleSelect').addEventListener('change',syncAccountType);
syncAccountType();
byId('searchForm').addEventListener('submit',event=>{event.preventDefault();refresh();});byId('refreshButton').addEventListener('click',refresh);
byId('logoutButton').addEventListener('click',async()=>{try{await api('/auth/logout',{method:'POST'});}catch{}showLogin();});
if(token){try{const user=JSON.parse(sessionStorage.getItem('buklinAdminUser'));showPanel(user);refresh();}catch{showLogin();}}else showLogin();
