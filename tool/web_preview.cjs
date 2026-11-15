// Loopback-only synthetic UI fixture. Never serves user-selected files.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../assets/web');
const files = [
  {name:'Project brief.pdf',path:'Project brief.pdf',size:2457600,mimeType:'application/pdf',isDirectory:false},
  {name:'Brand assets',path:'Brand assets',size:0,mimeType:'inode/directory',isDirectory:true},
  {name:'Notes.txt',path:'Notes.txt',size:2048,mimeType:'text/plain',isDirectory:false},
  {name:'CloudPocket.png',path:'CloudPocket.png',size:184320,mimeType:'image/png',isDirectory:false},
];
const types = {'.html':'text/html','.css':'text/css','.js':'application/javascript','.png':'image/png'};
const json = (response, value, code=200) => {response.writeHead(code, {'content-type':'application/json','cache-control':'no-store'});response.end(JSON.stringify(value));};
http.createServer((request,response) => {
  const url = new URL(request.url, 'http://127.0.0.1:18080');
  const cookies = Object.fromEntries((request.headers.cookie||'').split(';').filter(Boolean).map(value=>value.trim().split('=')));
  const mode = cookies.cp_preview_mode || 'send';
  const theme = cookies.cp_preview_theme || 'light';
  if (url.pathname === '/api/device-info') return json(response,{deviceName:'Preview device',themeMode:theme});
  if (url.pathname === '/api/security-mode') return json(response,{requirePassword:mode==='protected',requireGoogleAuth:false,allowUploads:mode==='receive'});
  if (url.pathname === '/api/register-visitor') return json(response,{success:true});
  if (url.pathname === '/api/auth/password') {response.setHeader('set-cookie','cp_preview_auth=1; Path=/; SameSite=Lax');return json(response,{success:true,fullyAuthenticated:true});}
  if (url.pathname === '/api/auth/logout') {response.setHeader('set-cookie','cp_preview_auth=; Max-Age=0; Path=/');return json(response,{success:true});}
  if (url.pathname === '/api/files') {
    if (mode==='protected' && !cookies.cp_preview_auth) return json(response,{error:'Authentication required'},401);
    return json(response,{items:mode==='receive'||url.searchParams.get('subpath')?[]:files,isReceiveMode:mode==='receive',allowUploads:mode==='receive'});
  }
  if (url.pathname === '/api/room/info') return json(response,{roomName:'Design review',roomCode:'AB-4829',requirePin:false,remainingSeconds:900,themeMode:theme});
  if (url.pathname === '/api/room/auth') return json(response,{success:true});
  if (url.pathname === '/api/thumbnail' || url.pathname === '/api/files/CloudPocket.png') {response.writeHead(200,{'content-type':'image/png'});return fs.createReadStream(path.join(root,'logo.png')).pipe(response);}
  if (url.pathname.startsWith('/api/files/')) {response.writeHead(200,{'content-type':'text/plain','content-disposition':'attachment; filename="preview.txt"'});return response.end('Synthetic CloudPocket preview. No personal data.');}
  if (url.pathname === '/api/upload') {let size=0;request.on('data',chunk=>size+=chunk.length);request.on('end',()=>json(response,{success:true,size,filename:'preview-upload'}));return;}
  let asset = url.pathname === '/' ? 'index.html' : url.pathname === '/room' ? 'room.html' : url.pathname.slice(1);
  if (url.searchParams.has('view') || url.searchParams.has('theme')) response.setHeader('set-cookie',[
    `cp_preview_mode=${['send','receive','protected'].includes(url.searchParams.get('view'))?url.searchParams.get('view'):'send'}; Path=/; SameSite=Lax`,
    `cp_preview_theme=${url.searchParams.get('theme')==='dark'?'dark':'light'}; Path=/; SameSite=Lax`,
  ]);
  const target = path.resolve(root,asset);
  if (!target.startsWith(root+path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {response.writeHead(404);return response.end('Not found');}
  response.writeHead(200,{'content-type':types[path.extname(target)]||'application/octet-stream','cache-control':'no-store'});
  fs.createReadStream(target).pipe(response);
}).listen(18080,'127.0.0.1',()=>console.log('Synthetic preview: http://127.0.0.1:18080/?view=send (receive/protected and theme=dark available)'));
