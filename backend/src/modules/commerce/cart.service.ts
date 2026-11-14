import {ConflictException,Inject,Injectable,NotFoundException,UnprocessableEntityException} from '@nestjs/common';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {PricingService} from '../pricing/pricing.service';
import {itemInclude} from '../catalog/catalog.mapper';
import {LoadedCart,CommerceStore,cartInclude} from './commerce.store';
import {CartPricingService,digest} from './cart-pricing.service';
import {exact} from '../pricing/pricing.calculator';
import {AddCartInput,AddressInput,QuantityInput,QuoteCartInput,VersionInput} from './commerce.dto';
import {Prisma} from '../../generated/prisma/client';
import {evaluateServiceability,serviceabilitySelect} from './serviceability';
type AddressRow={latitude:Prisma.Decimal|null;longitude:Prisma.Decimal|null;[k:string]:unknown};
/** Coordinates are returned only to the owning customer, as plain numbers. */
export const presentAddress=<T extends AddressRow>(a:T)=>({...a,latitude:a.latitude==null?null:Number(a.latitude),longitude:a.longitude==null?null:Number(a.longitude),hasConfirmedLocation:a.latitude!=null});
@Injectable()
export class CartService {
  constructor(@Inject(CommerceStore) readonly store:CommerceStore,@Inject(PricingService) readonly pricing:PricingService,@Inject(CartPricingService) readonly totals:CartPricingService){}
  private present(cart:LoadedCart){
    let subtotal=0n,itemCount=0;
    const items=cart.items.map(line=>{
      const base=BigInt(line.menuItem.basePricePaise),variant=BigInt(line.variant?.priceAdjustmentPaise??0);
      const addOns=line.addOns.reduce((s,a)=>s+BigInt(a.addOn.pricePaise),0n);
      const unit=base+variant+addOns,lineTotal=unit*BigInt(line.quantity);
      subtotal+=lineTotal;itemCount+=line.quantity;
      return {...line,unitPricePaise:exact(unit),lineTotalPaise:exact(lineTotal)};
    });
    return {...cart,items,itemCount,merchandiseSubtotalPaise:exact(subtotal)};
  }
  get(p:AuthenticatedPrincipal){return this.store.run(p,async tx=>this.present(await this.store.cart(tx,p.userId)));}
  add(p:AuthenticatedPrincipal,input:AddCartInput){return this.store.run(p,async tx=>{
    const cart=await this.store.cart(tx,p.userId);this.store.version(cart,input.expectedVersion);
    if(input.area)await this.pricing.validateArea(tx,input.area);
    const item=await tx.menuItem.findUnique({where:{id:input.menuItemId},include:itemInclude});
    if(!item)throw new NotFoundException('Menu item not found');
    const {variant,addOns}=this.pricing.selection(item,input,{skipZone:!input.area});
    if(cart.restaurantId&&cart.restaurantId!==input.restaurantId&&cart.items.length){
      if(!input.replaceRestaurant)throw new ConflictException('Your cart contains items from another restaurant. Replace your cart to continue?');
      await tx.cartItem.deleteMany({where:{cartId:cart.id}});
    }
    const selectionKey=digest({item:input.menuItemId,variant:variant?.id??null,addOns:addOns.map(a=>a.id).sort()});
    const existing=await tx.cartItem.findUnique({where:{cartId_selectionKey:{cartId:cart.id,selectionKey}}});
    const quantity=(existing?.quantity??0)+input.quantity;
    if(quantity>20)throw new UnprocessableEntityException('Maximum quantity is 20 per selection');
    if(!existing&&await tx.cartItem.count({where:{cartId:cart.id}})>=20)throw new UnprocessableEntityException('Maximum 20 cart selections');
    if(existing)await tx.cartItem.update({where:{id:existing.id},data:{quantity}});
    else await tx.cartItem.create({data:{cartId:cart.id,menuItemId:item.id,variantId:variant?.id,quantity,selectionKey,addOns:{create:addOns.map(a=>({addOnId:a.id}))}}});
    return this.present(await tx.cart.update({where:{id:cart.id},data:{restaurantId:input.restaurantId,version:{increment:1}},include:cartInclude}));
  });}
  change(p:AuthenticatedPrincipal,id:string|undefined,input:VersionInput|QuantityInput){return this.store.run(p,async tx=>{
    const cart=await this.store.cart(tx,p.userId);this.store.version(cart,input.expectedVersion);
    if(id&&!cart.items.some(i=>i.id===id))throw new NotFoundException('Cart item not found');
    if(id&&'quantity'in input)await tx.cartItem.update({where:{id},data:{quantity:input.quantity}});
    else await tx.cartItem.deleteMany({where:{cartId:cart.id,...(id?{id}:{})}});
    const remaining=await tx.cartItem.count({where:{cartId:cart.id}});
    return this.present(await tx.cart.update({where:{id:cart.id},data:{version:{increment:1},...(!remaining?{restaurantId:null}:{})},include:cartInclude}));
  });}
  quote(p:AuthenticatedPrincipal,input:QuoteCartInput){return this.store.run(p,async tx=>{
    const cart=await this.store.cart(tx,p.userId);this.store.version(cart,input.expectedVersion);
    const result=await this.totals.calculate(tx,cart,input.addressId,input.promotion);
    const quote=await tx.cartQuote.create({data:{cartId:cart.id,cartVersion:cart.version,addressId:input.addressId,promotion:input.promotion,fingerprint:result.fingerprint,expiresAt:result.expiresAt}});
    return {...result,quoteId:quote.id};
  });}
  addresses(p:AuthenticatedPrincipal){return this.store.run(p,async tx=>(await tx.customerAddress.findMany({where:{customerId:p.userId},orderBy:[{isDefault:'desc'},{createdAt:'desc'}],include:{locality:{select:{name:true}}}})).map(presentAddress));}
  saveAddress(p:AuthenticatedPrincipal,input:AddressInput,id?:string){return this.store.run(p,async tx=>{
    if(input.localityId)await this.pricing.validateArea(tx,input.localityId);
    const hasLat=input.latitude!=null,hasLng=input.longitude!=null;
    if(hasLat!==hasLng)throw new UnprocessableEntityException('Provide both latitude and longitude, or neither');
    if(hasLat&&!input.locationSource)throw new UnprocessableEntityException('locationSource is required with coordinates');
    if(!hasLat&&(input.locationSource||input.locationAccuracyMeters!=null))throw new UnprocessableEntityException('Location details require coordinates');
    // Ownership is enforced in the query itself: another customer's id is indistinguishable from a missing one.
    const current=id?await tx.customerAddress.findFirst({where:{id,customerId:p.userId}}):null;
    if(id&&!current)throw new NotFoundException('Address not found');
    const sameCoords=current&&hasLat&&current.latitude!=null&&Number(current.latitude)===Number(new Prisma.Decimal(input.latitude!).toFixed(6))&&Number(current.longitude)===Number(new Prisma.Decimal(input.longitude!).toFixed(6));
    const data={
      label:input.label,recipientName:input.recipientName,contactNumber:input.contactNumber,addressLine1:input.addressLine1,
      addressLine2:input.addressLine2,landmark:input.landmark,city:input.city,localityId:input.localityId??null,postalCode:input.postalCode,
      latitude:hasLat?new Prisma.Decimal(input.latitude!).toDecimalPlaces(6):null,
      longitude:hasLat?new Prisma.Decimal(input.longitude!).toDecimalPlaces(6):null,
      // Accuracy describes a device fix only; a hand-placed pin has no GPS accuracy.
      locationAccuracyMeters:hasLat&&input.locationSource==='DEVICE_GPS'?input.locationAccuracyMeters:null,
      locationSource:hasLat?input.locationSource:null,
      locationConfirmedAt:hasLat?(sameCoords?current!.locationConfirmedAt:new Date()):null,
    };
    if(!id){
      const existing=await tx.customerAddress.findFirst({where:{customerId:p.userId,label:data.label,recipientName:data.recipientName,contactNumber:data.contactNumber,addressLine1:data.addressLine1,addressLine2:data.addressLine2,landmark:data.landmark,city:data.city,localityId:data.localityId,postalCode:data.postalCode,latitude:data.latitude,longitude:data.longitude},orderBy:{createdAt:'desc'}});
      if(existing){
        if(input.isDefault){await tx.customerAddress.updateMany({where:{customerId:p.userId,isDefault:true},data:{isDefault:false}});return presentAddress(await tx.customerAddress.update({where:{id:existing.id},data:{isDefault:true}}));}
        return presentAddress(existing);
      }
    }
    if(!id&&await tx.customerAddress.count({where:{customerId:p.userId}})>=20)throw new UnprocessableEntityException('Maximum 20 saved addresses');
    if(input.isDefault)await tx.customerAddress.updateMany({where:{customerId:p.userId,isDefault:true},data:{isDefault:false}});
    const saved=id?await tx.customerAddress.update({where:{id},data:{...data,isDefault:input.isDefault}}):await tx.customerAddress.create({data:{...data,isDefault:input.isDefault,customerId:p.userId}});
    return presentAddress(saved);
  });}
  /** Per-restaurant delivery eligibility for one of the caller's own addresses. */
  serviceability(p:AuthenticatedPrincipal,id:string){return this.store.run(p,async tx=>{
    const address=await tx.customerAddress.findFirst({where:{id,customerId:p.userId},select:{id:true,localityId:true,latitude:true,longitude:true}});
    if(!address)throw new NotFoundException('Address not found');
    const area=address.localityId?await tx.locality.findFirst({where:{id:address.localityId,isActive:true},select:{id:true,name:true}}):null;
    const restaurants=await tx.restaurant.findMany({select:serviceabilitySelect,orderBy:[{displayOrder:'asc'},{id:'asc'}]});
    const effective={...address,localityId:area?.id??null};
    return {
      addressId:address.id,
      hasConfirmedLocation:address.latitude!=null,
      serviceArea:area,
      policy:'Verified straight-line radius when the restaurant pickup point is verified; otherwise configured service-area coverage (distance unverified). No road distance or ETA is calculated.',
      restaurants:restaurants.map(r=>evaluateServiceability(r,effective)),
    };
  });}
  deleteAddress(p:AuthenticatedPrincipal,id:string){return this.store.run(p,async tx=>{
    const deleted=await tx.customerAddress.deleteMany({where:{id,customerId:p.userId}});if(!deleted.count)throw new NotFoundException('Address not found');return {deleted:true};
  });}
}
