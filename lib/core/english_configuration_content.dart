/// Translates the built-in Vietnamese lists saved by earlier app versions.
/// Unrecognized custom lines, whitespace and line breaks are preserved.
String translateLegacyConfigurationContent(
  String value,
) => value.replaceAllMapped(RegExp(r'[^\r\n]+'), (match) {
  final line = match.group(0)!;
  final text = line.trim();
  final translated = _legacyContent[text];
  if (translated == null) return line;
  final start = line.indexOf(text);
  return '${line.substring(0, start)}$translated${line.substring(start + text.length)}';
});

const _legacyContent = <String, String>{
  'Du lịch Việt Nam': 'Travel in Vietnam',
  'Ẩm thực đường phố': 'Street food',
  'Công thức nấu ăn': 'Cooking recipes',
  'Công nghệ': 'Technology',
  'Review đồ gia dụng': 'Home appliance reviews',
  'Mẹo vặt cuộc sống': 'Life hacks',
  'Trang trí nhà cửa': 'Home decor',
  'Chăm sóc thú cưng': 'Pet care',
  'Làm vườn': 'Gardening',
  'Thiên nhiên': 'Nature',
  'Nhiếp ảnh': 'Photography',
  'Học tiếng Anh': 'Learning English',
  'Kiến thức khoa học': 'Science facts',
  'Sách hay': 'Book recommendations',
  'Thể thao': 'Sports',
  'Thời trang': 'Fashion',
  'Âm nhạc': 'Music',
  'Hội họa': 'Painting',
  'Cà phê': 'Coffee',
  'Đồ thủ công': 'Handmade crafts',
  'Video hay quá, xem không chán luôn!':
      'This video is so good, I could watch it all day!',
  'Nội dung chất lượng thật sự 👏': 'Such great content 👏',
  'Xem xong thấy vui cả ngày 😊': 'This made my whole day 😊',
  'Video cuốn quá, xem một lần chưa đủ!':
      'This video is so engaging, one watch is not enough!',
  'Cảm ơn bạn đã chia sẻ video này nhé ❤️':
      'Thank you for sharing this video ❤️',
  'Hay quá bạn ơi!': 'This is amazing!',
  'Nội dung thú vị ghê luôn.': 'Such interesting content.',
  'Xem mà không muốn lướt qua luôn 😍': 'I could not scroll past this 😍',
  'Tiếp tục phát huy nhé bạn!': 'Keep up the great work!',
  'Chờ video tiếp theo của bạn nha.': 'Looking forward to your next video.',
  'Video này xứng đáng được nhiều người xem hơn!':
      'This video deserves more attention!',
  'Quá tuyệt vời luôn 👍': 'Absolutely wonderful 👍',
  'Cách bạn chia sẻ rất dễ hiểu.': 'You explain things so clearly.',
  'Xem mà thấy cuốn thật sự.': 'This was such an engaging watch.',
  'Một chiếc video đầy năng lượng tích cực ✨':
      'A video full of positive energy ✨',
  'Nội dung rất hữu ích, cảm ơn bạn!': 'This is so helpful, thank you!',
  'Đỉnh quá bạn ơi 🔥': 'This is awesome 🔥',
  'Video chất lượng, ủng hộ bạn nhé!': 'Great video, happy to support you!',
  'Xem xong muốn xem thêm nữa.': 'I want to see more after watching this.',
  'Bạn làm video ngày càng hay đó!': 'Your videos keep getting better!',
  'Coi mà cười suốt luôn 😂': 'I could not stop laughing 😂',
  'Quá thú vị, cảm ơn bạn đã chia sẻ!':
      'So interesting, thank you for sharing!',
  'Góc nhìn hay và mới mẻ quá.': 'Such a fresh and interesting perspective.',
  'Video này đúng gu mình luôn.': 'This video is exactly my kind of content.',
  'Chúc kênh của bạn ngày càng phát triển ❤️':
      'Wishing your channel continued growth ❤️',
  'Thật sự rất đáng xem!': 'Definitely worth watching!',
  'Nội dung gần gũi và dễ thương quá.': 'Such relatable and lovely content.',
  'Xem video thấy thư giãn hẳn.': 'This video helped me relax.',
  'Cảm ơn bạn vì nội dung tuyệt vời này!':
      'Thank you for this wonderful content!',
  'Mong bạn ra thêm nhiều video như vậy.':
      'I hope you make more videos like this.',
  'Hay thật sự, không biết nói gì hơn 👏': 'So good, I am lost for words 👏',
  'Xem xong học được thêm nhiều điều.': 'I learned something new from this.',
  'Bạn chia sẻ có tâm quá!': 'You put so much care into what you share!',
  'Video này làm mình tò mò ghê.': 'This video really sparked my curiosity.',
  'Quá cuốn hút luôn bạn ơi!': 'This is so captivating!',
  'Một nội dung rất đáng để lưu lại.': 'This is definitely worth saving.',
  'Càng xem càng thấy hay.': 'It gets better the more I watch.',
  'Video dễ thương quá trời 🥰': 'This video is so cute 🥰',
  'Nội dung này đúng thứ mình đang tìm.':
      'This is exactly what I was looking for.',
  'Ủng hộ bạn hết mình nhé!': 'You have my full support!',
  'Bạn có nhiều ý tưởng hay thật đấy.': 'You have so many great ideas.',
  'Xem mà thấy thích quá!': 'I really enjoyed watching this!',
  'Video ngắn nhưng nội dung chất lượng.':
      'A short video packed with great content.',
  'Chia sẻ thêm nhiều điều thú vị nữa nhé.':
      'Please share more interesting things like this.',
  'Thật sự rất ấn tượng với video này.': 'This video really impressed me.',
  'Cách dựng video đẹp quá!': 'The editing looks great!',
  'Nội dung vừa hay vừa bổ ích.': 'Entertaining and informative content.',
  'Lướt trúng video hay rồi 😍': 'Glad I came across this great video 😍',
  'Chúc bạn luôn giữ được năng lượng này!':
      'I hope you keep this wonderful energy!',
  'Một video rất đáng để chia sẻ.': 'A video worth sharing.',
  'Xem xong chỉ muốn thả tim ❤️': 'This makes me want to leave a heart ❤️',
  'Video này có sức hút riêng thật.': 'This video has its own special charm.',
  'Nội dung tuyệt vời, tiếp tục nhé!': 'Wonderful content, keep it up!',
  'Cảm giác xem video rất thoải mái.': 'Watching this feels so relaxing.',
  'Quá xuất sắc luôn bạn!': 'Absolutely outstanding!',
  'Đây chính là lý do mình thích TikTok.': 'This is why I enjoy TikTok.',
  'Video hay, cách truyền tải cũng hay.': 'A great video with great delivery.',
  'Xem một mạch đến cuối luôn!': 'I watched it all the way through!',
  'Cảm ơn bạn đã mang đến nội dung ý nghĩa.':
      'Thank you for sharing something meaningful.',
  'Mong kênh sớm đạt nhiều lượt theo dõi nhé!':
      'I hope your channel reaches more people soon!',
  'Quá hợp lý luôn, cảm ơn bạn!': 'That makes so much sense, thank you!',
  'Video này khiến mình chú ý ngay từ đầu.':
      'This video caught my attention right away.',
  'Bạn làm nội dung rất có đầu tư.':
      'You clearly put a lot of effort into your content.',
  'Xem xong vẫn còn muốn xem lại.': 'I still want to watch it again.',
  'Một chiếc video thật nhiều cảm xúc 🥰': 'A video full of emotion 🥰',
  'Nội dung đơn giản mà hấp dẫn ghê.': 'Simple yet engaging content.',
  'Cứ tiếp tục sáng tạo nhé bạn!': 'Keep creating!',
  'Video này đáng được lan tỏa rộng rãi.': 'This video deserves to be shared.',
  'Thật sự thích cách bạn làm video.':
      'I really like your approach to making videos.',
  'Hay quá, cho bạn một lượt thích 👍': 'This is great, leaving a like 👍',
  'Xem mà quên cả thời gian luôn.': 'I lost track of time watching this.',
  'Nội dung tích cực như này rất đáng quý.':
      'Positive content like this is precious.',
  'Video đẹp mắt và cuốn hút quá!':
      'This video looks beautiful and is so engaging!',
  'Cảm ơn bạn đã dành thời gian chia sẻ.':
      'Thank you for taking the time to share this.',
  'Chất lượng quá, hóng phần tiếp theo!':
      'Great quality, looking forward to the next part!',
  'Bạn truyền tải nội dung rất tự nhiên.': 'Your delivery feels so natural.',
  'Video thú vị hơn mình tưởng luôn.':
      'This video was even more interesting than I expected.',
  'Xem xong cảm thấy có thêm động lực.':
      'I feel more motivated after watching this.',
  'Một nội dung rất đáng để trải nghiệm.': 'Definitely worth experiencing.',
  'Chúc bạn có thêm nhiều video triệu view!':
      'Wishing you many more million-view videos!',
  'Mình thích những video như thế này.': 'I enjoy videos like this.',
  'Xem rất cuốn, không bị nhàm chán.': 'Engaging from start to finish.',
  'Cách bạn kể chuyện hấp dẫn thật.': 'You are such a good storyteller.',
  'Nội dung hay, hình ảnh cũng đẹp nữa.':
      'Great content and beautiful visuals.',
  'Một video mang lại nhiều giá trị.': 'A video that offers real value.',
  'Rất thích sự sáng tạo của bạn ✨': 'I love your creativity ✨',
  'Xem xong thấy ngày hôm nay vui hơn.': 'This made my day a little brighter.',
  'Tiếp tục chia sẻ những điều tích cực nhé!': 'Keep sharing positive things!',
  'Video này làm tốt hơn mình mong đợi.':
      'This video exceeded my expectations.',
  'Quá tuyệt, mình sẽ theo dõi kênh!':
      'This is wonderful, I will follow your channel!',
  'Thả tim cho nội dung chất lượng ❤️':
      'Leaving a heart for quality content ❤️',
  'Video vừa thú vị vừa dễ hiểu.':
      'An interesting video that is easy to understand.',
  'Mong được xem nhiều nội dung hay hơn nữa.':
      'Looking forward to more great content.',
  'Bạn làm video có duyên thật đấy!':
      'You have such a natural charm on camera!',
  'Nội dung hấp dẫn từ đầu đến cuối.': 'Captivating from beginning to end.',
  'Một video rất đáng để dành thời gian xem.':
      'A video worth spending time on.',
  'Cảm ơn TikTok đã đề xuất video này 😄':
      'Thank you, TikTok, for recommending this 😄',
  'Hay quá, chúc bạn ngày càng thành công!':
      'This is great, wishing you continued success!',
  'Xem xong phải vào bình luận ngay!':
      'I had to leave a comment after watching this!',
  'Tiếp tục giữ phong độ nhé, mình ủng hộ bạn!':
      'Keep it up, you have my support!',
};
