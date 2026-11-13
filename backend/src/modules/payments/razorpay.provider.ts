import {Injectable,ServiceUnavailableException} from '@nestjs/common';
export function paymentConfig(){
  const keyId=process.env.RAZORPAY_KEY_ID??'',secret=process.env.RAZORPAY_KEY_SECRET??'';
  if(!['development','test'].includes(process.env.NODE_ENV??'')||!/^rzp_test_[A-Za-z0-9]+$/.test(keyId)||!secret)throw new ServiceUnavailableException('Razorpay Test Mode is not configured');
  return {keyId,secret};
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
