import {Inject,Injectable,NotFoundException,UnprocessableEntityException} from '@nestjs/common';
import {createHash} from 'node:crypto';
import {Prisma} from '../../generated/prisma/client';
import {PricingService} from '../pricing/pricing.service';
import {calculate,exact,QUOTE_TTL_MS} from '../pricing/pricing.calculator';
import {itemInclude} from '../catalog/catalog.mapper';
import {LoadedCart} from './commerce.store';
export const digest=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
export const CART_POLICY='cart-v1-order-fees';
@Injectable()
export class CartPricingService {
  constructor(@Inject(PricingService) readonly pricing:PricingService){}
  async calculate(tx:Prisma.TransactionClient,cart:LoadedCart,addressId:string,promotion?:string){
    if(!cart.restaurant||!cart.items.length)throw new UnprocessableEntityException('Your cart is empty');
    const address=await tx.customerAddress.findFirst({where:{id:addressId,customerId:cart.customerId},include:{locality:{select:{name:true}}}});
    if(!address)throw new NotFoundException('Delivery address not found');
    const area=await this.pricing.validateArea(tx,address.localityId),now=new Date();
    const rules=await this.pricing.rules(tx,area.id,now);
    const items=await tx.menuItem.findMany({where:{id:{in:cart.items.map(i=>i.menuItemId)}},include:itemInclude});
    const lines=cart.items.map(line=>{
      const item=items.find(i=>i.id===line.menuItemId);if(!item)throw new UnprocessableEntityException('A cart item is no longer available');
      const selected=this.pricing.selection(item,{restaurantId:cart.restaurantId!,menuItemId:item.id,area:area.id,quantity:line.quantity,variantId:line.variantId??undefined,addOnIds:line.addOns.map(a=>a.addOnId)});
      const variant=selected.variant?{id:selected.variant.id,name:selected.variant.name,priceAdjustmentPaise:selected.variant.priceAdjustmentPaise}:null;
      const addOns=selected.addOns.map(a=>({id:a.id,name:a.name,pricePaise:a.pricePaise})).sort((a,b)=>a.id.localeCompare(b.id));
      const basePaise=exact(BigInt(item.basePricePaise)*BigInt(line.quantity));
      const variantPaise=exact(BigInt(variant?.priceAdjustmentPaise??0)*BigInt(line.quantity));
      const addOnPaise=exact(BigInt(addOns.reduce((s,a)=>s+a.pricePaise,0))*BigInt(line.quantity));
      return {id:line.id,menuItemId:item.id,name:item.name,imageKey:item.imageKey,baseUnitPaise:item.basePricePaise,quantity:line.quantity,variant,addOns,basePaise,variantPaise,addOnPaise,lineTotalPaise:exact(BigInt(basePaise)+BigInt(variantPaise)+BigInt(addOnPaise))};
    });
    const sum=(key:'basePaise'|'variantPaise'|'addOnPaise')=>exact(lines.reduce((n,l)=>n+BigInt(l[key]),0n));
    // Aggregate merchandise first; invoke the existing exact rule engine once for the order.
    const {chosen,...totals}=calculate({basePricePaise:sum('basePaise'),variantPaise:sum('variantPaise'),addOnPaise:sum('addOnPaise'),quantity:1,restaurantId:cart.restaurantId!,area:area.id,promotion,rules,now});
    const snapshot={label:address.label,recipientName:address.recipientName,contactNumber:address.contactNumber,addressLine1:address.addressLine1,addressLine2:address.addressLine2,landmark:address.landmark,localityId:area.id,localityName:area.name,postalCode:address.postalCode};
    const pricingPolicyVersion=CART_POLICY+':'+digest(chosen).slice(0,24);
    const fingerprint=digest({cartId:cart.id,version:cart.version,lines,totals,snapshot,pricingPolicyVersion});
    const expiresAt=new Date(Math.min(now.getTime()+QUOTE_TTL_MS,...chosen.filter(r=>r.effectiveUntil).map(r=>r.effectiveUntil!.getTime())));
    return {cartId:cart.id,cartVersion:cart.version,restaurant:cart.restaurant,lines,...totals,address:snapshot,currency:'INR',pricingPolicyVersion,fingerprint,expiresAt,quotedAt:now,warnings:[],notice:'No real payment collected. Locality eligibility only; exact address routing is not verified.'};
  }
}
