Feature: 基础导航
  作为用户
  我希望能在各个页面之间切换
  以便查看不同的功能模块

  Scenario: 启动应用默认显示自选页
    Given 应用已启动
    Then 底部导航栏的自选Tab应该被选中
    And 页面应该显示自选列表区域

  Scenario: 切换到全市场页
    Given 应用已启动
    When 我点击底部导航栏的全市场Tab
    Then 底部导航栏的全市场Tab应该被选中
    And 页面应该显示全市场列表区域

  Scenario: 切换到行业页
    Given 应用已启动
    When 我点击底部导航栏的行业Tab
    Then 底部导航栏的行业Tab应该被选中
    And 页面应该显示行业列表区域

  Scenario: 切换到回踩页
    Given 应用已启动
    When 我点击底部导航栏的回踩Tab
    Then 底部导航栏的回踩Tab应该被选中
    And 页面应该显示回踩列表区域

  Scenario: 自选页内切换到持仓Tab
    Given 应用已启动
    And 当前在自选页
    When 我点击持仓Tab
    Then 应该显示持仓列表区域
    And 应该显示从截图导入按钮

  Scenario: 自选页内切换回自选Tab
    Given 应用已启动
    And 当前在自选页
    When 我点击持仓Tab
    And 我点击自选Tab
    Then 应该显示自选列表区域
    And 应该显示添加股票输入框
