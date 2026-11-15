import {Injectable,ServiceUnavailableException} from '@nestjs/common';
/** Razorpay TEST mode runs in development/test, or in production only with an explicit opt-in.
 * Only rzp_test_ keys are ever accepted, so no deployment can collect real money through this path. */
export function testPaymentsAllowed(){
  const env=process.env.NODE_ENV??'';
  return ['development','test'].includes(env)||(env==='production'&&process.env.PAYMENTS_TEST_MODE_ENABLED==='true');
}
/** No-payment demo checkout: development/test only, never production. */
export function demoCheckoutAllowed(){
  return ['development','test'].includes(process.env.NODE_ENV??'')&&process.env.DEMO_CHECKOUT_ENABLED==='true';
}
export function paymentConfig(){
  const keyId=process.env.RAZORPAY_KEY_ID??'',secret=process.env.RAZORPAY_KEY_SECRET??'';
  if(!testPaymentsAllowed()||!/^rzp_test_[A-Za-z0-9]+$/.test(keyId)||!secret)throw new ServiceUnavailableException('Razorpay Test Mode is not configured');
  return {keyId,secret};
}
/** What checkout may offer right now. Never includes key material. */
export function paymentMethods(){
  let razorpayTest=false;
  try{paymentConfig();razorpayTest=true;}catch{}
  const methods=[...(razorpayTest?['RAZORPAY_TEST']:[]),...(demoCheckoutAllowed()?['DEMO_NO_PAYMENT']:[])];
  return {methods,razorpayTest,demoCheckout:demoCheckoutAllowed(),testModeOnly:true};
}
export type ProviderOrder={id:string;amount:number;currency:string;receipt:string;status:string};
export type ProviderPayment={id:string;order_id:string;amount:number;currency:string;status:string;captured:boolean};
export abstract class PaymentProvider {
  abstract create(amount:number,receipt:string):Promise<ProviderOrder>;
  abstract find(receipt:string):Promise<ProviderOrder[]>;
  abstract payments(orderId:string):Promise<ProviderPayment[]>;
  abstract payment(id:string):Promise<ProviderPayment>;
}
@Injectable()
export class RazorpayProvider extends PaymentProvider {
  private async api(path:string,data?:object){
    const config=paymentConfig();
    try{
      const result=await fetch(`https://api.razorpay.com/v1/${path}`,{method:data?'POST':'GET',headers:{Authorization:'Basic '+Buffer.from(`${config.keyId}:${config.secret}`).toString('base64'),'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined,signal:AbortSignal.timeout(12000),redirect:'error'});
      if(!result.ok)throw new Error('Provider request failed');return await result.json();
    }catch{throw new ServiceUnavailableException('Payment provider is temporarily unavailable. Check payment status before retrying.');}
  }
  create(amount:number,receipt:string):Promise<ProviderOrder>{return this.api('orders',{amount,currency:'INR',receipt,partial_payment:false});}
  async find(receipt:string):Promise<ProviderOrder[]>{return (await this.api(`orders?receipt=${encodeURIComponent(receipt)}&count=100`)).items.filter((o:ProviderOrder)=>o.receipt===receipt);}
  async payments(orderId:string):Promise<ProviderPayment[]>{return (await this.api(`orders/${encodeURIComponent(orderId)}/payments`)).items;}
  payment(id:string):Promise<ProviderPayment>{return this.api(`payments/${encodeURIComponent(id)}`);}
}
