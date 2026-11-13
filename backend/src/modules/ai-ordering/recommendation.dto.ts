
import {
  IsDefined,
  IsObject,
  Matches,
} from 'class-validator';

export class RecommendationInput {
  @Matches(/^[a-z0-9-]{1,64}$/)
  area!: string;

  @IsDefined()
  @IsObject()
  intent!: Record<string, unknown>;
}
