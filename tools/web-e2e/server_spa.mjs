import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize } from "node:path";
const ROOT = process.argv[2], PORT = Number(process.argv[3]);
const T = {".html":"text/html",".js":"text/javascript",".mjs":"text/javascript",".css":"text/css",".json":"application/json",".png":"image/png",".wasm":"application/wasm",".otf":"font/otf",".ttf":"font/ttf",".ico":"image/x-icon",".svg":"image/svg+xml"};
createServer((req,res)=>{
  const u=new URL(req.url,"http://x"); let p=join(ROOT,normalize(decodeURIComponent(u.pathname)));
  if(!existsSync(p)||!statSync(p).isFile()) p=join(ROOT,"index.html");
  res.writeHead(200,{"Content-Type":T[extname(p)]??"application/octet-stream"}); res.end(readFileSync(p));
}).listen(PORT,()=>console.log("up",PORT));
