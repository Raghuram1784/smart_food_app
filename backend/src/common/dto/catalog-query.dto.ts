import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
export class CatalogQuery {
  @ApiPropertyOptional({default:1,minimum:1}) @Type(()=>Number) @IsInt() @Min(1) @Max(10000) page=1;
  @ApiPropertyOptional({default:20,maximum:50}) @Type(()=>Number) @IsInt() @Min(1) @Max(50) limit=20;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) @Transform(({value})=>typeof value==='string'?value.trim().replace(/\s+/g,' '):value) q?:string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) category?:string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) cuisine?:string;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) area?:string;
  @ApiPropertyOptional() @IsOptional() @Type(()=>Number) @IsInt() @Min(0) @Max(100000000) maxPricePaise?:number;
  /** Server-side food-type filter on MenuItem.isVegetarian. Omitted = both. */
  @ApiPropertyOptional({enum:['veg','nonveg']}) @IsOptional() @IsIn(['veg','nonveg']) diet?:'veg'|'nonveg';
}
export class IdParams {
  @Matches(/^[a-z0-9-]{1,64}$/) id!:string;
}
