import { Injectable, OnModuleInit } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
@Injectable()
export class PasswordService implements OnModuleInit {
  private dummy!: string;
  async onModuleInit() { this.dummy=await this.hash(randomBytes(32).toString('base64url')); }
  hash(password:string) { return argon2.hash(password,{type:argon2.argon2id,memoryCost:65536,timeCost:3,parallelism:1}); }
  async verify(hash:string|undefined,password:string) {
    try { return await argon2.verify(hash ?? this.dummy,password); } catch { return false; }
  }
}
