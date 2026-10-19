// 发邮件（登录验证码 + 约球邮件），Resend 发不出去就换 Mailjet。说明见 mail.ts
import { handle } from './mail.ts';

Deno.serve(handle);
