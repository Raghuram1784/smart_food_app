import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsEmail, IsString, Length, Matches, MaxLength } from 'class-validator';
export class LoginInput {
  @ApiProperty() @Transform(({value})=>typeof value==='string'?value.trim().toLowerCase():value)
  @IsEmail() @MaxLength(254) @Matches(/^[\x21-\x7e]+$/) email!: string;
  @ApiProperty({writeOnly:true}) @IsString() @Length(1,128) password!: string;
}
export class ProfileInput {
  @ApiProperty() @Transform(({value})=>typeof value==='string'?value.trim():value)
  @IsString() @Length(2,80) @Matches(/^[^\x00-\x1f\x7f]+$/) displayName!: string;
}
