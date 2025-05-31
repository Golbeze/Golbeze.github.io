---
layout: post
title:  "buusec_2019_code_review_1"
date:   2025-05-31 15:20:22 +0800
categories: web
---

# buusec_2019_code_review_1

[toc]

项目链接[buusec_2019_code_review_1](https://github.com/glzjin/buusec_2019_code_review_1/tree/master)

源码

```php
<?php
highlight_file(__FILE__);

class BUU {
   public $correct = "";
   public $input = "";

   public function __destruct() {
       try {
           $this->correct = base64_encode(uniqid());
           if($this->correct === $this->input) {
               echo file_get_contents("/flag");
           }
       } catch (Exception $e) {
       }
   }
}

if($_GET['pleaseget'] === '1') {
    if($_POST['pleasepost'] === '2') {
        if(md5($_POST['md51']) == md5($_POST['md52']) && $_POST['md51'] != $_POST['md52']) {
            unserialize($_POST['obj']);
        }
    }
}
```

## 难点

1. 同时满足GET与POST
2. 通过md5相等校验
3. 反序列化后的base64比较



## 解法

1. 使用hackerbar的enable Post data功能
   * 本质上是在post请求的路径里添加查询参数

2. 三种解法
   1. 传入数组, md5不能处理数组, 返回null
   2. 传入硬碰撞md5值
   3. 传入做md5 0e数字解析碰撞

3. 构造反序列化**php变量引用**
   * 对变量的别名, 类型相同, 本质上是指向同一块内存

