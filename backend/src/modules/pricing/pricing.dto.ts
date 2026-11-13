import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMaxSize, ArrayMinSize, ArrayUnique, IsArray, IsInt, IsOptional, IsUUID, Matches, Max, Min } from 'class-validator';

export class QuoteInput {
  @ApiProperty() @Matches(/^[a-z0-9-]{1,64}$/) restaurantId!: string;
  @ApiProperty() @Matches(/^[a-z0-9-]{1,64}$/) menuItemId!: string;
  @ApiProperty() @Matches(/^[a-z0-9-]{1,64}$/) area!: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() variantId?: string;
  @ApiPropertyOptional({ type: [String] }) @IsArray() @ArrayMaxSize(10) @ArrayUnique() @IsUUID('all', { each: true }) addOnIds: string[] = [];
  @ApiPropertyOptional({ default: 1, maximum: 20 }) @IsInt() @Min(1) @Max(20) quantity = 1;
  @ApiPropertyOptional() @IsOptional() @Matches(/^[A-Z0-9_-]{1,40}$/) promotion?: string;
}

export class CompareInput {
  @ApiProperty() @Matches(/^[a-z0-9-]{1,64}$/) area!: string;
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(2) @ArrayMaxSize(3) @ArrayUnique()
  @Matches(/^[a-z0-9-]{1,64}$/, { each: true }) itemIds!: string[];
}
