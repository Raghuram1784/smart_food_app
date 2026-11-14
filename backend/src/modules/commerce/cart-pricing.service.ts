import {Inject,Injectable,NotFoundException,UnprocessableEntityException} from '@nestjs/common';
import {createHash} from 'node:crypto';
import {Prisma} from '../../generated/prisma/client';
import {PricingService} from '../pricing/pricing.service';
import {calculate,exact,QUOTE_TTL_MS} from '../pricing/pricing.calculator';
import {itemInclude} from '../catalog/catalog.mapper';
import {LoadedCart} from './commerce.store';
import {evaluateServiceability,serviceabilitySelect} from './serviceability';
export const digest=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
export const CART_POLICY='cart-v1-order-fees';
@Injectable()
export class CartPricingService {
  constructor(@Inject(PricingService) readonly pricing:PricingService){}
  async calculate(tx:Prisma.TransactionClient,cart:LoadedCart,addressId:string,promotion?:string){
    if(!cart.restaurant||!cart.items.length)throw new UnprocessableEntityException('Your cart is empty');
    const address=await tx.customerAddress.findFirst({where:{id:addressId,customerId:cart.customerId},include:{locality:{select:{name:true}}}});
    if(!address)throw new NotFoundException('Delivery address not found');
    // Serviceability is enforced server-side for every quote and again at checkout (which re-quotes).
    const restaurant=await tx.restaurant.findUniqueOrThrow({where:{id:cart.restaurantId!},select:serviceabilitySelect});
    const serviceability=evaluateServiceability(restaurant,address);
    if(!serviceability.eligible)throw new UnprocessableEntityException(serviceability.reason);
    if(!address.localityId)throw new UnprocessableEntityException('Delivery fees are not configured for locations outside the current service areas.');
    const area=await this.pricing.validateArea(tx,address.localityId),now=new Date();
    const rules=await this.pricing.rules(tx,area.id,now);
    const items=await tx.menuItem.findMany({where:{id:{in:cart.items.map(i=>i.menuItemId)}},include:itemInclude});
    const lines=cart.items.map(line=>{
      const item=items.find(i=>i.id===line.menuItemId);if(!item)throw new UnprocessableEntityException('A cart item is no longer available');
      const selected=this.pricing.selection(item,{restaurantId:cart.restaurantId!,menuItemId:item.id,area:area.id,quantity:line.quantity,variantId:line.variantId??undefined,addOnIds:line.addOns.map(a=>a.addOnId)},{skipZone:serviceability.basis==='VERIFIED_DISTANCE'});
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
    const snapshot={label:address.label,recipientName:address.recipientName,contactNumber:address.contactNumber,addressLine1:address.addressLine1,addressLine2:address.addressLine2,landmark:address.landmark,city:address.city,localityId:area.id,localityName:area.name,postalCode:address.postalCode,
      // Confirmed delivery point (null for legacy/manual addresses). Visible only to the customer and assigned rider.
      location:address.latitude!=null?{latitude:Number(address.latitude),longitude:Number(address.longitude),source:address.locationSource}:null,
      serviceability:{status:serviceability.status,basis:serviceability.basis,straightLineMeters:serviceability.straightLineMeters}};
    const pricingPolicyVersion=CART_POLICY+':'+digest(chosen).slice(0,24);
    const fingerprint=digest({cartId:cart.id,version:cart.version,lines,totals,snapshot,pricingPolicyVersion});
    const expiresAt=new Date(Math.min(now.getTime()+QUOTE_TTL_MS,...chosen.filter(r=>r.effectiveUntil).map(r=>r.effectiveUntil!.getTime())));
    return {cartId:cart.id,cartVersion:cart.version,restaurant:cart.restaurant,lines,...totals,address:snapshot,currency:'INR',pricingPolicyVersion,fingerprint,expiresAt,quotedAt:now,warnings:[],notice:serviceability.basis==='VERIFIED_DISTANCE'?'No real payment collected. Delivery radius verified by straight-line distance; road route and ETA are not calculated.':'No real payment collected. Service-area eligibility only; exact delivery distance is not verified.'};
  }
}
