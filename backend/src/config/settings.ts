import 'dotenv/config';
export interface Settings { port:number; prefix:string; databaseUrl:string; origins:string[]; production:boolean; }
export function settings(env:NodeJS.ProcessEnv=process.env):Settings {
  const databaseUrl=env.DATABASE_URL;
  if(!databaseUrl || databaseUrl.includes('YOUR_PASSWORD')) throw new Error('Configure DATABASE_URL in backend/.env');
  let url:URL; try {url=new URL(databaseUrl);} catch {throw new Error('DATABASE_URL must be a PostgreSQL URL');}
  if(!['postgresql:','postgres:'].includes(url.protocol)||!url.hostname||!url.pathname.slice(1))throw new Error('DATABASE_URL must identify a PostgreSQL database');
  const port=Number(env.PORT??5000);
  if(!Number.isInteger(port)||port<1||port>65535)throw new Error('PORT must be 1–65535');
  const prefix=env.API_PREFIX??'api/v1';
  if(!/^api\/v\d+$/.test(prefix))throw new Error('API_PREFIX must match api/vN');
  const production=env.NODE_ENV==='production';
  if(production && !['require','verify-full'].includes(url.searchParams.get('sslmode')??''))throw new Error('Production PostgreSQL requires TLS');
  const origins=(env.CORS_ORIGINS??'http://localhost:3000').split(',').map(x=>x.trim()).filter(Boolean);
  if(origins.includes('*'))throw new Error('CORS_ORIGINS must list explicit origins');
  return {port,prefix,databaseUrl,origins,production};
}
