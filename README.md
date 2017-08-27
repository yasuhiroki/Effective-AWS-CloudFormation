Step by Step で始める AWS CloudFormation を少しでも楽にメンテする方法

# 概要

本記事では現時点[^1]で、私なりの CloudFormation を少しでも楽にメンテするためのノウハウを説明します。
[^1]: 2017/08/28

ただし、いきなり色々な機能をフル活用すると学習コストが高いので、Step by Step で少しずつメンテを楽にする手段を身に付けられるような構成を意識しています。

## この記事で触れること

- [AWS CloudFormation](https://aws.amazon.com/jp/cloudformation/) の (私なりの) 作成・メンテ手順
	- Templateファイルをどうやって書くか
	- スタックの作成、更新手順
- [AWS CloudFormation の組み込み関数](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference.html)
- [AWS CloudFormation Change Sets](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-changesets.html)
- [AWS CloudFormation Cross Stack Reference](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/walkthrough-crossstackref.html)
- [AWS CloudFormation カスタムリソース](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/template-custom-resources.html)
	- ただし、積極的な活用はせず、あくまで手段の1つとして触れています
	- 詳しくは後述しますが、CloudFormationで動的なコードを走らせるのはテスト・メンテが辛くなると考えています

## この記事で触れないこと

- AWS の説明
	- 「これから AWS を触るんです！」という方には色々と説明不足な点があると思いますがご了承下さい
- [CloudFormation ヘルパースクリプト](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/cfn-helper-scripts-reference.html)
	- `cfn-init` とか `cfn-signal` など
	- 私には説明できる自信がないので省いています[^2]

[^2]: そもそも使わなくて済むならなるべく使わない方が良いと考えています。数年前ならともかく、今なら代替手段があるはずです。

# Step1. CloudFormation Template を書こう

## Step1.1 Yamlで書こう

TBD

### なぜYamlなのか（なぜJsonがダメなのか）

TBD

### コメントを書こう

TBD

### ただし Yaml エイリアスは使えない

Yamlにはアンカー・エイリアス機能があるのですが、CloudFormationのTemplateとしては使えません。
例えば次のように `Subnet` の定義で共通部分（例えば VpcIdの部分）を使い回すようなYamlを書いても、CloudFormationでは使えません。

```yaml
Resources:
  PublicSubnetAZ1: &PublicSubnet
    Type: 'AWS::EC2::Subnet'
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [ 0, !GetAZs "" ]
      CidrBlock: !Ref PublicSubnetAZ1Cidr
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: public-subnet-AZ1
  PublicSubnetAZ2:
    <<: * PublicSubnet
    Properties:
      AvailabilityZone: !Select [ 1, !GetAZs "" ]
      CidrBlock: !Ref PublicSubnetAZ2Cidr
      Tags:
        - Key: Name
          Value: public-subnet-AZ2
```

```bash
# aws cloudformation validate-template 実行時にエラーとなる
An error occurred (ValidationError) when calling the ValidateTemplate operation: Template error: YAML aliases are not allowed in CloudFormation templates
```


使いたい場合は Ruby などで正規化されたYamlに変換する必要があります。

#### 番外編: Templateを分解すべきか

CloudFormationのTemplateが増えると、似た部分が多く出てくるようになるかもしれません。
それが「似ているけど違うもの」なら良いのですが「同じ情報を指すもの」であると、ダブルメンテが発生してメンテ性に欠けてしまうでしょう。どちらか一方を変更し、もう一方を変更し忘れた、というありがちなミスが発生しうる状態です。

打開策として、共通部分を別ファイルにしてしまう方法があります。

```bash
# _ec2 と _vpc の共通層を _common にまとめたとしたら
$ ls -1
_common.template.yaml
_ec2.template.yaml
_vpc.template.yaml

# こんな感じで合体させる
$ ruby -ryaml -ractive_support -e 'puts YAML.dump( YAML.load_file(ARGV[0]).deep_merge(YAML.load_file(ARGV[1])) )' _common.template.yaml _ec2.template.yaml > ec2.template.yaml
```

この例の場合、副次的効果としてYamlのアンカー・エイリアスを使うことができます。
しかし一方で、後述する Yaml の短縮形構文は使えません。短縮形構文はYamlのタグ機能[^3]を使っているのですが、このタグはAWS独自のタグなので、Rubyに読み込ませた時点で無視され、無くなってしまいます。  
[^3]: http://yaml.org/spec/1.2/spec.html#id2761292 ちなみにリンクは Yaml 1.2 ですが、Rubyが依存しているYamlは 1.1 です

ここからは個人の趣味の話になると思いますが、私は CloudFormation をプログラマブルにメンテするのは、かえって効率が悪いと考えています。
理由は、まず１つにCloudFormationを触るエンジニアがプログラマーとは限らない、というのものです。
そして、もう１つが、CloudFormation Templateは設計図であり、その設計図は他の設計図となるべく疎結合にしておいた方が、内容の把握・修正が容易になると考えているためです。設計図の組み方やいつものフレーズなどを過去から使いまわすのは良いですが、ある設計図を変更したら別の設計図の変更も必要だった、というのは避けるべきです。  

そのため、Templateファイルは多少同じような記述があってもダブルメンテ覚悟で管理し、代わりにツールを駆使してメンテ漏れに気付ける工夫をする方に手を動かしています。

雑な例だと次のような感じです。

```bash
# 別にコマンドラインでテストすることに拘っている訳ではないです
$ ruby -ryaml -e 'raise "should be allowed ci environment" unless YAML.load_file(ARGV[0])["Parameters"]["Environment"]["AllowedValues"].include?("ci")' ec2.template.yaml
-e:1:in `<main>': should be allowed ci environment (RuntimeError)
```

結局、プログラムでテストしてるじゃないか、という指摘を受けるかもしれませんが、Yamlをカスタムできる仕組みを自分たちで作ることと、Yamlの記述内容をテストするスクリプトを書くことでは、後者の方が敷居が低いと思ってます。

## Step1.2 Yamlの短縮形構文を書こう



# 参考

- [AWS CloudFormation のベストプラクティス](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/best-practices.html)
cl