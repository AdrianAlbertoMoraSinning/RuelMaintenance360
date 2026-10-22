import {defineConfig} from 'vite'
import {readFileSync,writeFileSync} from 'node:fs'
import {resolve} from 'node:path'
import {createHash} from 'node:crypto'
export default defineConfig({server:{allowedHosts:['terminal.local']},plugins:[{
 name:'ruel-deployment-version',apply:'build',
 closeBundle(){
  const html=readFileSync(resolve('dist/index.html'),'utf8')
  const entry=html.match(/<script[^>]*type="module"[^>]*src="([^"]+)"/)?.[1]
  const styles=[...html.matchAll(/<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)].map(match=>match[1]).sort()
  if(!entry)throw new Error('Deployment version requires a built application entry')
  const release=JSON.parse(readFileSync(resolve('package.json'),'utf8')).version,builtAt=new Date().toISOString()
  const version=createHash('sha256').update(JSON.stringify({release,entry,styles})).digest('hex').slice(0,20)
  writeFileSync(resolve('dist/index.html'),html.replace('</head>',`<meta name="ruel-release" content="${release}"/><meta name="ruel-build" content="${version}"/><meta name="ruel-built-at" content="${builtAt}"/></head>`))
  writeFileSync(resolve('dist/app-version.json'),JSON.stringify({schema:1,version,entry,styles}))
 }
}]})
