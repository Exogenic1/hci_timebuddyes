import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isFromLeader;
  final String senderName;
  final Timestamp? timestamp;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.isFromLeader,
    required this.senderName,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        bottom: 8,
        left: isMe ? 64 : 8,
        right: isMe ? 8 : 64,
      ),
      child: Material(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(isMe ? 12 : 0),
          bottomRight: Radius.circular(isMe ? 0 : 12),
        ),
        elevation: 2,
        color: isMe
            ? Theme.of(context).primaryColor
            : isFromLeader
                ? Colors.amber[100]
                : Colors.grey[200],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Row(
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isFromLeader ? Colors.orange[800] : Colors.black,
                      ),
                    ),
                    if (isFromLeader)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.orange,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(text),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  timestamp != null
                      ? DateFormat('h:mm a').format(timestamp!.toDate())
                      : '--:--',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
