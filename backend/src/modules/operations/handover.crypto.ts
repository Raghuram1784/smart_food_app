import {ServiceUnavailableException} from '@nestjs/common';
import {createCipheriv,createDecipheriv,createHmac,randomBytes,randomInt,timingSafeEqual} from 'node:crypto';

export interface PinBinding {
  orderId:string; assignmentId:string; boundRiderId:string; challengeVersion:number;
  issuedAt:Date; expiresAt:Date; keyVersion:string;
}
export function handoverConfig(){
  const verify=process.env.HANDOVER_HMAC_KEY, encrypt=process.env.HANDOVER_ENCRYPTION_KEY;
  const keyVersion=process.env.HANDOVER_KEY_VERSION??'v1';
  const ttl=Number(process.env.HANDOVER_TTL_SECONDS??600);
  const cooldown=Number(process.env.HANDOVER_REGENERATE_SECONDS??60);
  if(!verify||!encrypt||!/^[a-f0-9]{64}$/i.test(verify)||!/^[a-f0-9]{64}$/i.test(encrypt)||verify.toLowerCase()===encrypt.toLowerCase()||!/^[-a-zA-Z0-9_]{1,40}$/.test(keyVersion)||!Number.isInteger(ttl)||ttl<60||ttl>900||!Number.isInteger(cooldown)||cooldown<30||cooldown>600){
    throw new ServiceUnavailableException('Secure handover is not configured');
  }
  return {verifyKey:Buffer.from(verify,'hex'),encryptionKey:Buffer.from(encrypt,'hex'),keyVersion,ttl,cooldown,maxAttempts:5,maxIssues:3,lockSeconds:300};
}
export function formatPin(value:number){
  if(!Number.isInteger(value)||value<0||value>=1000000)throw new Error('Invalid PIN entropy');
  return value.toString().padStart(6,'0');
}
export function generatePin(){return formatPin(randomInt(0,1000000));}
function binding(b:PinBinding){return JSON.stringify([b.orderId,b.assignmentId,b.boundRiderId,b.challengeVersion,b.issuedAt.toISOString(),b.expiresAt.toISOString(),b.keyVersion]);}
export function pinVerifier(pin:string,b:PinBinding,key:Buffer){
  return createHmac('sha256',key).update('food-delivery:handover:verify:v1\0').update(binding(b)).update('\0').update(pin).digest('hex');
}
export function matchesPin(pin:string,b:PinBinding,verifier:string,key:Buffer){
  if(!/^\d{6}$/.test(pin)||!/^[a-f0-9]{64}$/.test(verifier))return false;
  return timingSafeEqual(Buffer.from(pinVerifier(pin,b,key),'hex'),Buffer.from(verifier,'hex'));
}
export function sealPin(pin:string,b:PinBinding,key:Buffer){
  const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,nonce);
  cipher.setAAD(Buffer.from('food-delivery:handover:display:v1\0'+binding(b)));
  const encrypted=Buffer.concat([cipher.update(pin,'utf8'),cipher.final()]);
  return Buffer.concat([nonce,cipher.getAuthTag(),encrypted]).toString('base64');
}
export function openPin(payload:string,b:PinBinding,key:Buffer){
  try{
    const bytes=Buffer.from(payload,'base64');if(bytes.length!==34)throw Error();
    const decipher=createDecipheriv('aes-256-gcm',key,bytes.subarray(0,12));
    decipher.setAAD(Buffer.from('food-delivery:handover:display:v1\0'+binding(b)));
    decipher.setAuthTag(bytes.subarray(12,28));
    const pin=Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]).toString('utf8');
    if(!/^\d{6}$/.test(pin))throw Error();return pin;
  }catch{throw new ServiceUnavailableException('Secure handover could not be read');}
}
