import {Type,Transform} from 'class-transformer';
import {ArrayMaxSize,ArrayUnique,IsArray,IsBoolean,IsIn,IsInt,IsOptional,IsString,IsUUID,Length,Matches,Max,Min} from 'class-validator';
const trim=({value}:{value:unknown})=>typeof value==='string'?value.trim():value;
export class VersionInput { @IsInt() @Min(1) expectedVersion!:number; }
export class AddCartInput extends VersionInput {
  @IsString() @Matches(/^[a-z0-9-]{1,64}$/) restaurantId!:string;
  @IsString() @Matches(/^[a-z0-9-]{1,64}$/) menuItemId!:string;
  @IsString() @Matches(/^[a-z0-9-]{1,64}$/) area!:string;
  @IsOptional() @IsUUID() variantId?:string;
  @IsArray() @ArrayMaxSize(10) @ArrayUnique() @IsUUID('all',{each:true}) addOnIds:string[]=[];
  @IsInt() @Min(1) @Max(20) quantity!:number;
  @IsOptional() @IsBoolean() replaceRestaurant=false;
}
export class QuantityInput extends VersionInput { @IsInt() @Min(1) @Max(20) quantity!:number; }
export class QuoteCartInput extends VersionInput {
  @IsUUID() addressId!:string;
  @IsOptional() @IsString() @Matches(/^[A-Z0-9_-]{1,80}$/) promotion?:string;
}
export class PlaceOrderInput {
  @IsUUID() cartId!:string;
  @IsUUID() addressId!:string;
  @IsUUID() quoteId!:string;
  @IsUUID() idempotencyKey!:string;
  @IsIn(['DEMO_NO_PAYMENT','RAZORPAY_TEST']) paymentMethod!:'DEMO_NO_PAYMENT'|'RAZORPAY_TEST';
}
export class AddressInput {
  @Transform(trim) @IsString() @Length(1,40) label!:string;
  @Transform(trim) @IsString() @Length(2,80) recipientName!:string;
  @Transform(trim) @IsString() @Matches(/^(?:\+91)?[6-9][0-9]{9}$/) contactNumber!:string;
  @Transform(trim) @IsString() @Length(5,200) addressLine1!:string;
  @Transform(trim) @IsString() @Length(0,200) addressLine2='';
  @Transform(trim) @IsString() @Length(0,120) landmark='';
  @IsString() @Matches(/^[a-z0-9-]{1,64}$/) localityId!:string;
  @IsString() @Matches(/^[1-9][0-9]{5}$/) postalCode!:string;
  @IsBoolean() isDefault=false;
}
export class UuidParam { @IsUUID() id!:string; }
export class RestaurantParam { @IsString() @Matches(/^[a-z0-9-]{1,64}$/) restaurantId!:string; }
export class OrderPage {
  @Type(()=>Number) @IsInt() @Min(1) @Max(10000) page=1;
  @Type(()=>Number) @IsInt() @Min(1) @Max(30) limit=10;
}
