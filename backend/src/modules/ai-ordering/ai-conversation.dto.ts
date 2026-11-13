
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID, Matches } from 'class-validator';
import { InterpretInput } from './ai-ordering.dto';

export class AskInput extends InterpretInput {
  @Matches(/^[a-z0-9-]{1,64}$/)
  area!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  conversationId?: string;
}
