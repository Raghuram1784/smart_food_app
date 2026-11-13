import { Global, Injectable, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { settings } from '../config/settings';
import { createDatabase } from './client';
@Injectable()
export class DatabaseService implements OnModuleInit,OnModuleDestroy {
  readonly client=createDatabase(settings().databaseUrl);
  async onModuleInit(){await this.client.$connect();}
  async onModuleDestroy(){await this.client.$disconnect();}
}
@Global()
@Module({providers:[DatabaseService],exports:[DatabaseService]})
export class DatabaseModule{}
