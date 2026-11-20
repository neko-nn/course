# core/bus.py
from core.message import Message

class MessageBus:
    def __init__(self):
        # 1. 通讯录（存智能体实例）
        self.agents = {}
        
        # 2. 权限硬约束表
        self.permissions = {
            "梓涵": {"子涵", "芷涵", "子晗", "子寒"}, 
            "子涵": {"梓涵"},
            "芷涵": {"梓涵"},
            "子晗": {"梓涵"},
            "子寒": {"梓涵"}
        }

    def register_agent(self, name: str, agent_instance):
        """将 NPC 注册到通讯录中"""
        self.agents[name] = agent_instance
        print(f"[总线] {name} 已接入小镇网络。")

    def send(self, message: Message) -> str:
        """发送消息，并返回接收方的回复内容（如果有的话）"""
        sender = message.sender
        receiver = message.receiver

        # 【第一关】查权限
        if sender not in self.permissions or receiver not in self.permissions[sender]:
            print(f"[总线拦截] 权限拒绝：{sender} 无权联系 {receiver}！")
            return "权限拒绝，无法发送。"

        # 【第二关】查通讯录，对方在不在线
        if receiver not in self.agents:
            print(f"[总线拦截] 发送失败：{receiver} 不在线。")
            return "接收方不在线。"

        # 【第三关】真实送达
        print(f"\n  [真实通信] {sender} => {receiver} : {message.content}")
        
        # 从通讯录里叫出接收方 NPC
        target_agent = self.agents[receiver]
        
        # 让接收方干活（调用它的 run 方法）
        # 注意：这里会阻塞等待接收方思考完并返回结果
        reply_text = target_agent.run(message.content)
        
        print(f"  [真实通信] {receiver} => {sender} : {reply_text[:20]}...")
        
        # 返回回复内容，调用方（比如 ask_npc 工具）会拿去用
        return reply_text