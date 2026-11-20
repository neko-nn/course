from typing import Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field

class Message(BaseModel):
    """智能体之间通信的统一消息信封"""
    sender: str
    receiver: str
    content: str
    msg_type: str = "query"  
    timestamp: datetime = Field(default_factory=datetime.now)
    metadata: Optional[Dict[str, Any]] = None
    correlation_id: Optional[str] = None
    
    def __str__(self) -> str:
        return f"[{self.timestamp.strftime('%H:%M:%S')}] {self.sender} -> {self.receiver} ({self.msg_type}): {self.content}"