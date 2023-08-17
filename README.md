# zbit
A BitTorrent client library written in Zig

## Roadmap
- BEP-0003:
  * [ ] Download single file
  * [ ] Smart piece request (bitfield/peer-messages)
  * [ ] Verify SHA1 pieces
  * [ ] Re-fetching on hash failure
  * [ ] Request pipelining
  * [ ] Support torrent with multiple files
  * [ ] Serve files
  * [ ] Persistant download states
  * [ ] Async hash verification
  * [ ] Async peer fetching
  * [ ] Peer discovery during download
  * [ ] Notify tracker of events
  * [ ] Reconnect to peers on disconnect
- [ ] Multi-tracker (BEP-0012)
- [ ] Compact peer list from tracker (BEP-0023)
- [ ] Piece download priority (rarest first)
- [ ] Fast extension (BEP-0006)
- [ ] UDP
- [ ] Extension messages
- [ ] Local Service Discovery (BEP-0014)
