import {IsUUID,Matches} from 'class-validator';
export class PaymentOrderInput {@IsUUID() orderId!:string;}
export class PaymentVerifyInput {
  @IsUUID() attemptId!:string;
  @Matches(/^order_[A-Za-z0-9]{1,60}$/) razorpay_order_id!:string;
  @Matches(/^pay_[A-Za-z0-9]{1,60}$/) razorpay_payment_id!:string;
  @Matches(/^[a-fA-F0-9]{64}$/) razorpay_signature!:string;
}
