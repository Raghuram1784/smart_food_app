import { Controller, Get, Inject, Module, ServiceUnavailableException } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { DatabaseService } from '../../database/database.module';
@ApiTags('Health') @Controller('health')
export class HealthController {
 constructor(@Inject(DatabaseService) private readonly db:DatabaseService){}
 @Get() async health(){try{await this.db.client.$queryRaw`SELECT 1`;return {status:'ok',database:'up'};}catch{throw new ServiceUnavailableException('Database unavailable');}}
}
@Module({controllers:[HealthController]}) export class HealthModule{}
