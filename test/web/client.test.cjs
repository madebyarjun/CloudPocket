const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {apply} = require('../../assets/web/theme.js');
function portal() {
  const nodes = new Map();
  const element = () => ({style:{},classList:{add(){},remove(){},toggle(){}},attributes:{},listeners:{},setAttribute(k,v){this.attributes[k]=v;},getAttribute(k){return this.attributes[k];},addEventListener(k,v){this.listeners[k]=v;},querySelectorAll(){return [];},appendChild(){},removeChild(){}});
  const get = id => {if (!nodes.has(id)) nodes.set(id,element()); return nodes.get(id);};
  class XHR {
    constructor(){XHR.last=this;this.upload={};this.status=0;}
    open(){} setRequestHeader(){} send(){} abort(){this.onabort();}
  }
  class WS {static OPEN=1;static CONNECTING=0; constructor(){WS.last=this;this.readyState=1;}send(){} }
  const context = vm.createContext({console,URL,URLSearchParams,Map,Set,Date,Math,Promise,Blob,TextEncoder,
    document:{getElementById:get,querySelector:()=>element(),querySelectorAll:()=>[],addEventListener(){},documentElement:element(),body:element(),visibilityState:'visible'},
    window:{addEventListener(){},location:{protocol:'http:',host:'localhost',search:'',href:'http://localhost/'}},
    localStorage:{getItem(){return null;},setItem(){},removeItem(){}},navigator:{onLine:true},
    XMLHttpRequest:XHR,WebSocket:WS,setInterval:()=>1,clearInterval(){},setTimeout:fn=>{fn();return 1;},clearTimeout(){}});
  vm.runInContext(fs.readFileSync('assets/web/app.js','utf8'),context);
  return {context,nodes,XHR,WS,run: code=>vm.runInContext(code,context)};
}
test('host theme applies explicit light/dark and restores system preference',()=>{
  const attrs={}; const doc={documentElement:{setAttribute:(k,v)=>attrs[k]=v,removeAttribute:k=>delete attrs[k]}};
  apply('dark',doc);assert.equal(attrs['data-theme'],'dark');apply('light',doc);assert.equal(attrs['data-theme'],'light');apply('system',doc);assert.equal(attrs['data-theme'],undefined);
});
test('upload rejection retains HTTP status so 4xx errors cannot be retried',async()=>{
  const p=portal();const result=p.run("uploadSingleFile({name:'file.txt',size:3},()=>{})");
  p.XHR.last.status=403;p.XHR.last.responseText='{"message":"Uploads disabled"}';p.XHR.last.onload();
  await assert.rejects(result,e=>e.status===403 && e.message==='Uploads disabled');
});
test('host cancellation aborts the matching browser request with terminal cancellation',async()=>{
  const p=portal();p.run('initWebSocket()');
  const result=p.run("uploadSingleFile({name:'file.txt',size:3},()=>{})");
  p.WS.last.onmessage({data:JSON.stringify({type:'transfer_cancelled',filename:'file.txt'})});
  await assert.rejects(result,e=>e.cancelled===true);
});
test('failed batch does not claim 100 percent completion or keep the busy flag',async()=>{
  const p=portal();p.run("withTransferLock=async fn=>fn();waitForVisibilityOrOnline=async()=>{};requestWebWakeLock=async()=>{};loadFiles=()=>{};uploadSingleFile=async()=>{const e=new Error('Forbidden');e.status=403;throw e;}");
  await p.run("uploadFiles([{name:'bad.txt',size:3}])");
  assert.equal(p.nodes.get('transferProgressText').textContent,'Incomplete');assert.equal(p.run('isUploadingLocal'),false);
});
test('view selection exposes its active state to assistive technology',()=>{
  const p=portal();p.run('renderFiles=()=>{}');p.nodes.get('viewListBtn').listeners.click();
  assert.equal(p.nodes.get('viewListBtn').attributes['aria-pressed'],'true');assert.equal(p.nodes.get('viewGridBtn').attributes['aria-pressed'],'false');
});
test('plaintext fallback is limited to local HTTP and never public HTTP or HTTPS',()=>{
  const source=fs.readFileSync('assets/web/room.js','utf8');
  const start=source.indexOf('  function isLocalHttpChat()');
  const end=source.indexOf('  function updateChatSecurity()',start);
  const context=vm.createContext({window:{location:{protocol:'http:',hostname:'192.168.1.2'}}});
  vm.runInContext(source.slice(start,end),context);
  for(const host of ['192.168.1.2','10.0.0.1','172.16.0.2','localhost','phone.local','[::1]']) {
    context.window.location.hostname=host;assert.equal(vm.runInContext('isLocalHttpChat()',context),true,host);
  }
  for(const host of ['bore.pub','8.8.8.8','172.32.0.1','192.168.1.999','example.com']) {
    context.window.location.hostname=host;assert.equal(vm.runInContext('isLocalHttpChat()',context),false,host);
  }
  context.window.location={protocol:'https:',hostname:'192.168.1.2'};assert.equal(vm.runInContext('isLocalHttpChat()',context),false);
});
