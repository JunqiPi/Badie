// 访客报名：先核对人机验证，再调数据库。说明见 signup.ts
import { handle } from './signup.ts';

Deno.serve(handle);
