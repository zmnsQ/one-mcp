export const tunnelErrors = {
 TUNNEL_TARGET:'隧道目标或操作类型无效，请重新选择连接。',
 TUNNEL_PROFILE:'Profile 名称无效，请使用字母、数字、下划线或短横线；已有文件请使用完整路径。',
 TUNNEL_ID:'Tunnel ID 格式无效，请填写官方返回的完整 tunnel_ ID。',
 TUNNEL_EXECUTABLE:'官方 tunnel-client 路径无效或不可执行，请在设置中重新选择已安装程序。',
 TUNNEL_KEY_FORMAT:'本次会话密钥格式无效，请重新输入；不会读取或复制已有凭据。',
 TUNNEL_PROFILE_FILE:'OneMCP 启动前检查：所选 Profile 文件路径无效、不存在或不可读取。请检查连接面板中显示的文件。',
 TUNNEL_PROFILE_LOOKUP:'官方客户端报告 Profile 或配置文件无法找到或读取。请核对连接面板显示的查找位置，不要重复初始化覆盖已有配置。',
 TUNNEL_EXISTING_INIT:'已选择现有 Profile 文件，不能再次初始化覆盖。请直接运行 Doctor 或启动。',
 TUNNEL_BACKEND:'请先启动这个独立出口对应的 MCP 服务，再连接隧道。',
 TUNNEL_BUSY:'此隧道操作仍在运行，请等待完成或明确停止后重试。',
 TUNNEL_DUPLICATE:'这个 Profile 或 Tunnel ID 已被另一个连接使用，请检查当前连接。',
 TUNNEL_KEY_REQUIRED:'官方客户端未能解析运行密钥。若 Profile 使用 env: 引用，请提供本次会话密钥；若使用 file: 引用，请检查原凭据文件。',
 TUNNEL_AUTH:'官方客户端报告认证或权限失败，请检查 Runtime key 的有效性及隧道 Read/Use 权限。',
 TUNNEL_UPSTREAM:'官方客户端无法连接 MCP 地址，请确认对应 MCP 已启动并检查连接目标。',
 TUNNEL_FAILED:'官方客户端未成功完成操作。请检查所选 Profile 和 Doctor 结果；为保护凭据，不显示原始输出。'
} as const;
export type TunnelErrorCode=keyof typeof tunnelErrors;
export class TunnelActionError extends Error {constructor(readonly code:TunnelErrorCode){super(`[${code}] ${tunnelErrors[code]}`);}}
export function safeTunnelError(error:unknown):string|undefined {
 const message=error instanceof Error?error.message:'';
 const code=message.match(/^\[(TUNNEL_[A-Z_]+)\]/)?.[1] as TunnelErrorCode|undefined;
 return code && code in tunnelErrors ? `[${code}] ${tunnelErrors[code]}` : undefined;
}
export function classifyTunnelDiagnostic(text:string):TunnelErrorCode|undefined {
 if(/(?:api.?key|control_plane.api_key|CONTROL_PLANE_API_KEY).{0,80}(?:missing|required|not set|empty|resolve)|(?:missing|required).{0,80}(?:api.?key|CONTROL_PLANE_API_KEY)/i.test(text))return 'TUNNEL_KEY_REQUIRED';
 if(/(?:profile|config).{0,80}(?:no such file|not found|permission denied)/i.test(text))return 'TUNNEL_PROFILE_LOOKUP';
 if(/unauthorized|forbidden|status(?: code)?[ :=]+(?:401|403)/i.test(text))return 'TUNNEL_AUTH';
 if(/connection refused|MCP.{0,80}(?:unreachable|connection failed)/i.test(text))return 'TUNNEL_UPSTREAM';
 return undefined;
}
