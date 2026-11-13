import {ConflictException,Inject,Injectable,NotFoundException,UnprocessableEntityException} from '@nestjs/common';
import {AuthenticatedPrincipal} from '../auth/auth.types';
import {PricingService} from '../pricing/pricing.service';
import {itemInclude} from '../catalog/catalog.mapper';
import {LoadedCart,CommerceStore,cartInclude} from './commerce.store';
import {CartPricingService,digest} from './cart-pricing.service';
import {exact} from '../pricing/pricing.calculator';
import {AddCartInput,AddressInput,QuantityInput,QuoteCartInput,VersionInput} from './commerce.dto';
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
    await this.pricing.validateArea(tx,input.area);
    const item=await tx.menuItem.findUnique({where:{id:input.menuItemId},include:itemInclude});
    if(!item)throw new NotFoundException('Menu item not found');
    const {variant,addOns}=this.pricing.selection(item,input);
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
  addresses(p:AuthenticatedPrincipal){return this.store.run(p,tx=>tx.customerAddress.findMany({where:{customerId:p.userId},orderBy:[{isDefault:'desc'},{createdAt:'desc'}],include:{locality:{select:{name:true}}}}));}
  saveAddress(p:AuthenticatedPrincipal,input:AddressInput,id?:string){return this.store.run(p,async tx=>{
    await this.pricing.validateArea(tx,input.localityId);
    if(id&&!await tx.customerAddress.findFirst({where:{id,customerId:p.userId}}))throw new NotFoundException('Address not found');
    if(!id){
      const {isDefault,...fields}=input;
      const existing=await tx.customerAddress.findFirst({where:{...fields,customerId:p.userId},orderBy:{createdAt:'desc'}});
      if(existing){
        if(isDefault){await tx.customerAddress.updateMany({where:{customerId:p.userId,isDefault:true},data:{isDefault:false}});return tx.customerAddress.update({where:{id:existing.id},data:{isDefault:true}});}
        return existing;
      }
    }
    if(!id&&await tx.customerAddress.count({where:{customerId:p.userId}})>=20)throw new UnprocessableEntityException('Maximum 20 saved addresses');
    if(input.isDefault)await tx.customerAddress.updateMany({where:{customerId:p.userId,isDefault:true},data:{isDefault:false}});
    return id?tx.customerAddress.update({where:{id},data:input}):tx.customerAddress.create({data:{...input,customerId:p.userId}});
  });}
  deleteAddress(p:AuthenticatedPrincipal,id:string){return this.store.run(p,async tx=>{
    const deleted=await tx.customerAddress.deleteMany({where:{id,customerId:p.userId}});if(!deleted.count)throw new NotFoundException('Address not found');return {deleted:true};
  });}
}
