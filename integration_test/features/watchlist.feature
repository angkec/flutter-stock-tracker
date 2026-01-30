Feature: 自选股管理
  作为用户
  我希望能管理我的自选股列表
  以便追踪我关注的股票

  Background:
    Given 应用已启动
    And 自选股列表已清空

  Scenario: 空自选列表显示提示
    Then 应该显示暂无自选股提示
    And 应该显示添加提示文字

  Scenario: 添加有效股票代码到自选
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示已添加提示
    And 自选列表应该包含该股票

    Examples:
      | string |
      | 000001 |
      | 600000 |
      | 300001 |

  Scenario: 添加无效股票代码
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示无效股票代码提示

    Examples:
      | string |
      | 123456 |
      | 999999 |
      | 12345  |

  Scenario: 添加重复股票代码
    Given 自选列表包含 {string}
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示该股票已在自选列表中提示

    Examples:
      | string |
      | 000001 |

  Scenario: 长按删除自选股
    Given 自选列表包含 {string}
    When 我长按列表中的该股票
    Then 应该显示已移除提示
    And 自选列表不应包含该股票

    Examples:
      | string |
      | 000001 |

  Scenario: 自选股列表数据持久化
    Given 自选列表包含 {string}
    When 我重启应用
    Then 自选列表应该包含该股票

    Examples:
      | string |
      | 000001 |
