#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
计算Solidity事件Topics的工具脚本
使用正确的eth-hash库计算Keccak256
"""

from eth_hash.auto import keccak

def keccak256(data):
    """
    计算Keccak256哈希
    使用eth-hash库，这是以太坊官方使用的算法
    """
    if isinstance(data, str):
        data = data.encode('utf-8')
    
    # 使用eth-hash的keccak函数
    hash_bytes = keccak(data)
    return hash_bytes.hex()

def verify_transfer_event():
    """
    验证Transfer事件的Topic计算
    """
    print("=== 验证Transfer事件Topic ===")
    
    # 已知的正确值
    correct_topic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    event_signature = "Transfer(address,address,uint256)"
    
    print(f"事件签名: {event_signature}")
    print(f"已知正确Topic: {correct_topic}")
    
    # 计算Topic
    calculated_topic = "0x" + keccak256(event_signature)
    print(f"计算得到Topic: {calculated_topic}")
    
    # 比较
    if calculated_topic.lower() == correct_topic.lower():
        print("✓ 计算正确！")
        return True
    else:
        print("✗ 计算错误！")
        print(f"差异: {calculated_topic} vs {correct_topic}")
        return False

def calculate_burn_for_parent_token():
    """
    计算BurnForParentToken事件的Topics
    """
    print("\n=== 计算BurnForParentToken事件Topics ===")
    
    # 事件签名
    event_signature = "BurnForParentToken(address,uint256,uint256)"
    print(f"事件签名: {event_signature}")
    
    # 计算Topic 0 (事件签名的Keccak256哈希)
    topic0 = keccak256(event_signature)
    print(f"Topic 0: 0x{topic0}")
    
    print("\n=== Topics结构分析 ===")
    print("Topic 0: 事件签名哈希 (固定值)")
    print("Topic 1: burner地址 (indexed参数)")
    print("Topic 2: 不存在 (burnAmount不是indexed)")
    print("Topic 3: 不存在 (parentTokenAmount不是indexed)")
    
    print("\n=== 事件数据(data) ===")
    print("burnAmount (uint256)")
    print("parentTokenAmount (uint256)")
    
    print(f"\n=== 总结 ===")
    print(f"总Topics数量: 2")
    print(f"Topic 0: 0x{topic0}")
    print(f"Topic 1: burner地址 (动态值)")
    
    return topic0

def calculate_other_events():
    """
    计算其他常见事件的Topics
    """
    print("\n\n=== 其他常见事件Topics ===")
    
    events = [
        "Transfer(address,address,uint256)",
        "Approval(address,address,uint256)",
        "TokenMint(address,uint256)",
        "TokenBurn(address,uint256)"
    ]
    
    for event in events:
        topic = keccak256(event)
        print(f"{event}: 0x{topic}")

def verify_mystery_topic():
    """
    验证神秘的Topic 0x33051b7b99352b2f771717639e25e4bf8dc930b1d6f8530cdc36d0fad8a922d5
    """
    print("\n\n=== 验证神秘Topic ===")
    mystery_topic = "0x33051b7b99352b2f771717639e25e4bf8dc930b1d6f8530cdc36d0fad8a922d5"
    print(f"神秘Topic: {mystery_topic}")
    
    # 尝试一些可能的事件签名
    possible_signatures = [
        "BurnForParentToken(address,uint256,uint256)",
        "Transfer(address,address,uint256)",
        "Approval(address,address,uint256)",
        "TokenMint(address,uint256)",
        "TokenBurn(address,uint256)",
        "Mint(address,uint256)",
        "Burn(address,uint256)",
        "Vote(address,uint256,address,uint256,uint256)",
        "Stake(address,uint256)",
        "Unstake(address,uint256)",
        "Join(address,uint256)",
        "Launch(address,uint256)",
        "Submit(address,uint256)",
        "Verify(address,uint256)"
    ]
    
    print("\n尝试匹配可能的事件签名:")
    for sig in possible_signatures:
        calculated_topic = "0x" + keccak256(sig)
        if calculated_topic.lower() == mystery_topic.lower():
            print(f"✓ 找到匹配! {sig}")
            return sig, mystery_topic
        else:
            print(f"✗ {sig}: {calculated_topic}")
    
    print("\n没有找到匹配的事件签名")
    return None, mystery_topic

if __name__ == "__main__":
    # 首先验证Transfer事件
    transfer_correct = verify_transfer_event()
    
    if not transfer_correct:
        print("\n⚠️  警告：Transfer事件计算不正确，可能存在算法问题！")
        print("需要检查Keccak256实现...")
    
    # 计算BurnForParentToken事件
    topic0 = calculate_burn_for_parent_token()
    
    # 计算其他事件
    calculate_other_events()
    
    # 验证神秘Topic
    matched_event, mystery_topic = verify_mystery_topic()
    
    print(f"\n=== 最终结果 ===")
    print(f"BurnForParentToken的Topic 0: 0x{topic0}")
    if matched_event:
        print(f"神秘Topic {mystery_topic} 对应事件: {matched_event}")
    else:
        print(f"神秘Topic {mystery_topic} 没有找到对应的事件")
