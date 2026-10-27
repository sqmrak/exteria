// secret chat payloads, layers 17 to 151, names that repeat across layers carry a crc-line pragma
decryptedMessageLayer#1be31789 random_bytes:bytes layer:int in_seq_no:int out_seq_no:int message:DecryptedMessage = DecryptedMessageLayer;

decryptedMessage_layer17#204d3878 random_id:long ttl:int message:string media:DecryptedMessageMedia = DecryptedMessage; // crc-line: decryptedMessage random_id:long ttl:int message:string media:DecryptedMessageMedia = DecryptedMessage
decryptedMessage_layer45#36b091de flags:# random_id:long ttl:int message:string media:flags.9?DecryptedMessageMedia entities:flags.7?Vector<MessageEntity> via_bot_name:flags.11?string reply_to_random_id:flags.3?long = DecryptedMessage; // crc-line: decryptedMessage flags:# random_id:long ttl:int message:string media:flags.9?DecryptedMessageMedia entities:flags.7?Vector<MessageEntity> via_bot_name:flags.11?string reply_to_random_id:flags.3?long = DecryptedMessage
decryptedMessage#91cc4674 flags:# silent:flags.5?true random_id:long ttl:int message:string media:flags.9?DecryptedMessageMedia entities:flags.7?Vector<MessageEntity> via_bot_name:flags.11?string reply_to_random_id:flags.3?long grouped_id:flags.17?long = DecryptedMessage;
decryptedMessageService#73164160 random_id:long action:DecryptedMessageAction = DecryptedMessage;

decryptedMessageMediaEmpty#089f5c4a = DecryptedMessageMedia;
decryptedMessageMediaPhoto_layer8#32798a8c thumb:bytes thumb_w:int thumb_h:int w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia; // crc-line: decryptedMessageMediaPhoto thumb:bytes thumb_w:int thumb_h:int w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia
decryptedMessageMediaPhoto#f1fa8d78 thumb:bytes thumb_w:int thumb_h:int w:int h:int size:int key:bytes iv:bytes caption:string = DecryptedMessageMedia;
decryptedMessageMediaVideo_layer8#4cee6ef3 thumb:bytes thumb_w:int thumb_h:int duration:int w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia; // crc-line: decryptedMessageMediaVideo thumb:bytes thumb_w:int thumb_h:int duration:int w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia
decryptedMessageMediaVideo_layer17#524a415d thumb:bytes thumb_w:int thumb_h:int duration:int mime_type:string w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia; // crc-line: decryptedMessageMediaVideo thumb:bytes thumb_w:int thumb_h:int duration:int mime_type:string w:int h:int size:int key:bytes iv:bytes = DecryptedMessageMedia
decryptedMessageMediaVideo#970c8c0e thumb:bytes thumb_w:int thumb_h:int duration:int mime_type:string w:int h:int size:int key:bytes iv:bytes caption:string = DecryptedMessageMedia;
decryptedMessageMediaGeoPoint#35480a59 lat:double long:double = DecryptedMessageMedia;
decryptedMessageMediaContact#588a0a97 phone_number:string first_name:string last_name:string user_id:int = DecryptedMessageMedia;
decryptedMessageMediaDocument_layer8#b095434b thumb:bytes thumb_w:int thumb_h:int file_name:string mime_type:string size:int key:bytes iv:bytes = DecryptedMessageMedia; // crc-line: decryptedMessageMediaDocument thumb:bytes thumb_w:int thumb_h:int file_name:string mime_type:string size:int key:bytes iv:bytes = DecryptedMessageMedia
decryptedMessageMediaDocument_layer45#7afe8ae2 thumb:bytes thumb_w:int thumb_h:int mime_type:string size:int key:bytes iv:bytes attributes:Vector<DocumentAttribute> caption:string = DecryptedMessageMedia; // crc-line: decryptedMessageMediaDocument thumb:bytes thumb_w:int thumb_h:int mime_type:string size:int key:bytes iv:bytes attributes:Vector<DocumentAttribute> caption:string = DecryptedMessageMedia
decryptedMessageMediaDocument#6abd9782 thumb:bytes thumb_w:int thumb_h:int mime_type:string size:long key:bytes iv:bytes attributes:Vector<DocumentAttribute> caption:string = DecryptedMessageMedia; // crc-skip: layout read from the working client TLRPC.java, the published line is unknown
decryptedMessageMediaAudio_layer8#6080758f duration:int size:int key:bytes iv:bytes = DecryptedMessageMedia; // crc-line: decryptedMessageMediaAudio duration:int size:int key:bytes iv:bytes = DecryptedMessageMedia
decryptedMessageMediaAudio#57e0a9cb duration:int mime_type:string size:int key:bytes iv:bytes = DecryptedMessageMedia;
decryptedMessageMediaExternalDocument#fa95b0dd id:long access_hash:long date:int mime_type:string size:int thumb:PhotoSize dc_id:int attributes:Vector<DocumentAttribute> = DecryptedMessageMedia;
decryptedMessageMediaVenue#8a0df56f lat:double long:double title:string address:string provider:string venue_id:string = DecryptedMessageMedia;
decryptedMessageMediaWebPage#e50511d8 url:string = DecryptedMessageMedia;

decryptedMessageActionSetMessageTTL#a1733aec ttl_seconds:int = DecryptedMessageAction;
decryptedMessageActionReadMessages#0c4f40be random_ids:Vector<long> = DecryptedMessageAction;
decryptedMessageActionDeleteMessages#65614304 random_ids:Vector<long> = DecryptedMessageAction;
decryptedMessageActionScreenshotMessages#8ac1f475 random_ids:Vector<long> = DecryptedMessageAction;
decryptedMessageActionFlushHistory#6719e45c = DecryptedMessageAction;
decryptedMessageActionResend#511110b0 start_seq_no:int end_seq_no:int = DecryptedMessageAction;
decryptedMessageActionNotifyLayer#f3048883 layer:int = DecryptedMessageAction;
decryptedMessageActionTyping#ccb27641 action:SendMessageAction = DecryptedMessageAction;
decryptedMessageActionRequestKey#f3c9611b exchange_id:long g_a:bytes = DecryptedMessageAction;
decryptedMessageActionAcceptKey#6fe1735b exchange_id:long g_b:bytes key_fingerprint:long = DecryptedMessageAction;
decryptedMessageActionAbortKey#dd05ec6b exchange_id:long = DecryptedMessageAction;
decryptedMessageActionCommitKey#ec2e0b9b exchange_id:long key_fingerprint:long = DecryptedMessageAction;
decryptedMessageActionNoop#a82fdd63 = DecryptedMessageAction;

documentAttributeVideo_secret#5910cccb duration:int w:int h:int = DocumentAttribute; // crc-line: documentAttributeVideo duration:int w:int h:int = DocumentAttribute
documentAttributeSticker_layer23#fb0a5727 = DocumentAttribute; // crc-line: documentAttributeSticker = DocumentAttribute
