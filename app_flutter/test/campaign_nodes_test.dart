import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/services/campaign_service.dart';

void main() {
  test('nhánh khuyến mãi rác (trường trộn ở gốc) không tạo dòng trống', () {
    final garbage = {
      'active': false,
      'campaignId': '',
      'campaignType': 'BILLDISCOUNT',
      'name': '',
      'schedule': {'timezone': 'Asia/Ho_Chi_Minh'},
    };
    expect(parseCampaignNodes(garbage), isEmpty);
  });

  test('lấy khóa node làm id khi thiếu campaignId; bỏ node hỏng', () {
    final list = parseCampaignNodes({
      'CAM_1': {'campaignType': 'BILLDISCOUNT', 'name': 'Giảm 10%', 'programCode': 'KM1'},
      'CAM_2': {'campaignId': 'CAM_2', 'campaignType': 'BILLDISCOUNT', 'name': 'B'},
      'x': 'chuỗi lạ',
      'y': {'name': 'không có campaignType'},
    });
    expect(list.map((c) => c.campaignId).toSet(), {'CAM_1', 'CAM_2'});
  });

  test('id rỗng hoặc có ký tự đường dẫn bị từ chối', () {
    expect(isValidCampaignId(''), isFalse);
    expect(isValidCampaignId('a/b'), isFalse);
    expect(isValidCampaignId('CAM_171_ab'), isTrue);
  });
}
