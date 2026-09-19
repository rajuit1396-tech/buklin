import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source=await readFile(new URL('../public/admin.js',import.meta.url),'utf8');
function setup({createFails=false,refreshFails=false}={}) {
  const elements=new Map();
  const element=id=>{
    if(!elements.has(id)) elements.set(id,{value:id==='roleSelect'?'customer':'',hidden:false,
      handlers:{},addEventListener(type,handler){this.handlers[type]=handler;},
      setAttribute(){},reset(){this.resets=(this.resets||0)+1;},replaceChildren(){},append(){}});
    return elements.get(id);
  };
  const values={name:'Test Customer',phone:'+966501234567',username:'new_customer',
    password:'NewPassword123',role:'customer',store_number:'007'};
  const context={document:{getElementById:element,createElement:()=>({append(){}})},
    sessionStorage:{getItem:()=>null,removeItem(){},setItem(){}},
    setTimeout:()=>0,clearTimeout(){},
    FormData:class {constructor(form){assert.ok(form);}get(key){return values[key];}},
    fetch:async path=>{
      if(path==='/admin/users') return {ok:!createFails,status:createFails?409:201,
        json:async()=>createFails?{error:'Username already exists'}:{user:{username:values.username}}};
      return {ok:!refreshFails,status:refreshFails?500:200,
        json:async()=>refreshFails?{error:'Refresh failed'}:path==='/admin/dashboard'?{totals:{}}:{users:[]}};
    }};
  vm.runInNewContext(source,context);
  return {element,async submit(){
    const form=element('accountForm'),button={disabled:false,textContent:'Create account'};
    const event={currentTarget:form,submitter:button,preventDefault(){}};
    const pending=form.handlers.submit(event);
    // Browsers clear currentTarget when synchronous event dispatch finishes.
    event.currentTarget=null;
    await pending;return button;
  }};
}
test('account success survives async event cleanup and refresh failure',async()=>{
  for(const refreshFails of [false,true]) {
    const {element,submit}=setup({refreshFails});
    const button=await submit();
    assert.equal(element('accountForm').resets,1);
    assert.equal(element('accountResult').hidden,false);
    assert.match(element('accountResult').textContent,/Account created successfully for @new_customer/);
    assert.equal(element('accountResult').className,'account-result success');
    assert.equal(button.disabled,false);
  }
});
test('failed account creation preserves form and displays the server error',async()=>{
  const {element,submit}=setup({createFails:true});
  const button=await submit();
  assert.equal(element('accountForm').resets,undefined);
  assert.equal(element('accountResult').textContent,'Username already exists');
  assert.equal(element('accountResult').className,'account-result error');
  assert.equal(button.disabled,false);
});
