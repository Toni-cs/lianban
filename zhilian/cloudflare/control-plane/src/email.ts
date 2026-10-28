export interface TransactionalEmailSender {
  send(message: {
    to: string;
    from: { email: string; name: string };
    subject: string;
    html: string;
    text: string;
  }): Promise<void>;
}

export interface OTPEmailInput {
  email: string;
  otp: string;
  type: "sign-in" | "email-verification" | "forget-password" | "change-email";
}

const SUBJECTS = {
  "sign-in": "联伴登录验证码",
  "email-verification": "验证你的联伴邮箱",
  "forget-password": "重置联伴密码",
  "change-email": "确认联伴邮箱变更",
} as const satisfies Record<OTPEmailInput["type"], string>;

export function buildOTPEmail(from: string, input: OTPEmailInput) {
  const subject = SUBJECTS[input.type];
  const text = `${subject}\n\n你的一次性验证码是：${input.otp}\n\n验证码 10 分钟内有效。如果不是你本人操作，可以忽略这封邮件。`;
  const html = `<!doctype html><html><body><h1>${subject}</h1><p>你的一次性验证码是：</p><p style="font-size:32px;font-weight:700;letter-spacing:0.15em">${input.otp}</p><p>验证码 10 分钟内有效。如果不是你本人操作，可以忽略这封邮件。</p></body></html>`;
  return {
    to: input.email,
    from: { email: from, name: "联伴" },
    subject,
    html,
    text,
  };
}

export async function sendOTPEmail(
  sender: TransactionalEmailSender,
  from: string,
  input: OTPEmailInput,
  requestId: string,
): Promise<void> {
  try {
    await sender.send(buildOTPEmail(from, input));
  } catch {
    // Authentication responses stay enumeration-safe. Do not log the address,
    // code, provider error, message object, or any other credential material.
    console.error(JSON.stringify({ message: "transactional email send failed", requestId }));
  }
}
