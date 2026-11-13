import { ApiProperty, ApiPropertyOptional, OmitType } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsDefined, IsIn, IsInt, IsNumber, IsOptional, Matches, Max, Min } from 'class-validator';
import { CatalogQuery } from '../../common/dto/catalog-query.dto';

export class SmartQuery extends OmitType(CatalogQuery, ['area'] as const) {
  @ApiProperty() @IsDefined() @Matches(/^[a-z0-9-]{1,64}$/) declare area: string;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100000000) maxPayablePaise?: number;
  @ApiPropertyOptional() @IsOptional() @Transform(({value}) => value === 'true' ? true : value === 'false' ? false : value) @IsBoolean() vegetarian?: boolean;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(180) maxMinutes?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(5) minRating?: number;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[a-z0-9-]{1,64}$/) restaurantId?: string;
  @ApiPropertyOptional({enum:['value','price','time','rating','relevance']}) @IsIn(['value','price','time','rating','relevance']) sort: 'value'|'price'|'time'|'rating'|'relevance' = 'value';
}
