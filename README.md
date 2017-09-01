Step by Step で始める AWS CloudFormation を少しでも楽にメンテする方法

# 概要

本記事では私なりの CloudFormation を少しでも楽にメンテするノウハウを説明します。

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
	- 私には説明できる自信がないので省いています[^1]
- CloudFormationを操作する権限管理
  - CloudFormationの操作はしても良いけど、EC2やS3などには直接触ってほしくない場合のIAM設定方法
  - IAM設計が絡むと本記事では扱いきれないので触れません

[^1]: ヘルパースクリプトはなるべく使わない方が良いと考えています。数年前ならともかく、今なら代替手段があるはずです。

# Step1. CloudFormation Template を書こう

TBD

## Step1.1 Yamlで書こう

CloudFormationのTemplateファイルはYamlで書くことが出来ます。[^2] 書きましょう。Jsonを使うメリットはさしてありません。配列の最後に `,` を書いてしまってFormatエラーになる日々をわざわざ選ぶ必要はないのです。
[^2]: [2016/09で公式にYamlがサポートされるようになりました](https://aws.amazon.com/jp/about-aws/whats-new/2016/09/aws-cloudformation-introduces-yaml-template-support-and-cross-stack-references/)

### Yaml のメリットを活かそう

YamlはJsonと違ってコメントが書けます。
プログラミングと同様、Templateを見ただけでは分からない情報を補完して「なぜその設定なのか」が分かるようにすると役に立つでしょう。

```yaml
Resources:
  # ユーザーがアップロードした画像の保存先S3
  S3Bucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      # ユーザーがアップロードした画像は公開される
      # いずれ公開・非公開を制御できるようにする
      AccessControl: PublicRead
      LifecycleConfiguration:
        Rules:
          # 保持期間は1日
          - Status: Enabled
            ExpirationInDays: 1
```

### ただし Yaml エイリアスは使えない

Yamlにはアンカー・エイリアス機能があるのですが、CloudFormationのTemplateとしては使えません。
例えば次のように `Subnet` の定義で共通部分（例えば VpcIdの部分）を使い回すようなYamlを書いても、CloudFormationでは使えません。  

次のようにアンカーを使っても、

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

aws cloudformation validate-template 実行時にエラーとなります。

```bash:
An error occurred (ValidationError) when calling the ValidateTemplate operation: Template error: YAML aliases are not allowed in CloudFormation templates
```

アンカー・エイリアスを使いたい場合は Ruby などで変換する必要があります。

### Yamlの短縮形構文を使おう

TBD

### 番外編: Templateの共通化をすべきか

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

この例の場合、Rubyを経由したことによる副次的効果としてYamlのアンカー・エイリアスを使うことができます。
しかし一方で、後述する Yaml の短縮形構文は使えません。短縮形構文はYamlのタグ機能[^3]を使っているのですが、このタグはAWS独自のタグなので、Rubyに読み込ませた時点で無視され、無くなってしまうのです。  
[^3]: http://yaml.org/spec/1.1/current.html#id858600

ここからは個人の趣味の話になると思いますが、私は CloudFormation をプログラマブルにメンテするのは、かえって効率が悪いと考えています。[^4]
理由は、まず１つにCloudFormationを触るエンジニアがプログラマーとは限らない、というのものです。
そして、もう１つが、CloudFormation Templateは設計図であり、その設計図は他の設計図となるべく疎結合にしておいた方が、内容の把握・修正が容易になると考えているためです。設計図の組み方やいつものフレーズなどを過去から使いまわすのは良いですが、ある設計図を変更したら別の設計図の変更も必要だった、というのは避けるべきです。プログラミングならば、疎結合にしつつ共通化するようデザインするところですが、CloudFormationでそこまでするメリットは果たしてあるのか悩ましいところです。  

そのため、Templateファイルは多少同じような記述があってもダブルメンテ覚悟で管理し、代わりにツールを駆使してメンテ漏れに気付ける工夫をする方にコストを割くようにしています。
こうしておけば、サービスの規模が大きくなってCloudFormationの共通部分が肥大化したのでまとめたくなった際に、テストしながら移行することが可能になります。  

次の例は、ec2.template.yaml は ci 環境用のParameterを許可しているか確認する簡単なスクリプトです。

```bash
$ ruby -ryaml -e 'raise "should be allowed ci environment" unless YAML.load_file(ARGV[0])["Parameters"]["Environment"]["AllowedValues"].include?("ci")' ec2.template.yaml
-e:1:in `<main>': should be allowed ci environment (RuntimeError)
```

結局、プログラムでテストしてるじゃないか、という指摘を受けるかもしれませんが、Yamlをカスタムできる仕組みを自分たちで作ることと、Yamlの記述内容をテストするスクリプトを書くことでは、後者の方が敷居が低く取り入れやすいと思うのです。

[^4]: 実際にCloudFormationの共通化をしたことがあるのですが、どこまでを共通化するか、共通化の仕組み・仕様はどんなか、共通化よるデグレなどがないか確認する方法、それらのドキュメント整備など作業が多く、費用対効果が適切ではないと感じました。ただ、共通化の仕組み自体は既存のツールを組み合わせればそれほどコストが掛からないと思うので、いずれ私の意見は変わる可能性があります。

## Step1.2 CloudFormation Designer を使おう

TBD

## Step1.3 CloudFormation の記法を活用しよう

Yamlの短縮形構文でも述べたように、 CloudFormationには固有のパラメータや記法が存在します。これらを活用することで、Yamlという静的なファイルでありながら、ある程度のプログラマブルな処理を記述することができます。詳しくは公式ドキュメントを参照頂くとして、私がどのように活用しているかご紹介します。

### 組み込み関数と疑似パラメーターを活用しよう

まずはCloudFormationの組み込み関数と疑似パラメータを簡単に紹介して、その後簡単なサンプルを例示しながら説明します。

#### 組み込み関数

組み込み関数は現時点で11種類あります。[^4] 条件関数にはさらに何種類かあるので、実際は11種類より多いです。
これらの関数をプログラマーの視点で分類してみます。

[^4]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference.html

- 条件分岐
- 文字列操作系
    - `Fn::Base64`  
      与えられた文字列をBase64する
    - `Fn::Join`  
      与えられた配列を区切り文字で連結する  
      `["a", "b"].join("-")` のような感じ
    - `Fn::Split`  
      与えられた文字列を区切り文字で分割して配列にする  
      `"a-b".split("-")` のような感じ
    - `Fn::Sub`  
      Rubyで言うと `"hoge-#{val}-fuga` のような文字列を定義し、`val` に代入されている値で文字列を作ることができる
- 配列操作系
    - `Fn::Join`  
      与えられた配列を区切り文字で連結する  
      `["a", "b"].join("-")` のような感じ
    - `Fn::Select`  
      与えられた配列から、与えられた添字の値を取得する  
      `arr[0]` のような感じ
    - `Fn::Split`  
      与えられた文字列を区切り文字で分割して配列にする  
      `"a-b".split("-")` のような感じ
- AWS CloudFormation 特有のもの
    - `Fn::FindInMap`  
      `Mappings` で定義した値を参照する際に使用する
    - `Fn::GetAtt`  
      AWSリソースを指定して、リソースからArnなどの値を取得する
    - `Fn::GetAZs`  
      指定したRegionが持つAvailabilityZoneの配列を取得する
    - `Fn::ImportValue`  
      Cross-stack referenceにより別StackでExportした値を取得する  
      詳しくは後述 #TODO: リンク
    - `Ref`  
      `Parameters` 及び `Resources` で定義した値を取得する際に使用する  
      特に `Resources` で定義した値を指定した場合は、どのような値を取得するかはリソースによって変わる  
      詳しくは後述 #TODO: リンク  

どれも便利な関数です。特に `Ref` は使わずにいる方が難しい関数でしょう。
また、`!Sub` は比較的新しい関数[^6]なので古い記事では見つからないかもしれません。しかし、かなり便利な関数です。ぜひ活用しましょう。

[^6]: 2016/09に追加された関数です TODO:Link

#### 疑似パラメータ

疑似パラメータ[^5] は、たとえるならCloudFormationが持つグローバル変数のようなものです。どのCloudFormationでも、特に何の前準備も無しに参照できるパラメータです。  
現時点では次の5種類が使えます。

[^5]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/pseudo-parameter-reference.html

- `AWS::AccountId`
  - AWSアカウントIdを取得する
- `AWS::NotificationARNs`
  - Stackの通知を受け取るSNSのArn
- `AWS::NoValue`
  - `Fn::If` と組み合わせて使う
  - Productionの時はこのパラメータは設定しない、とできる
- `AWS::Region`
  - Stackを作成したRegionの文字列
- `AWS::StackName`
  - その名の通りStack名

こちらも便利なものばかりです。例えば `AWS::AccountId` や `AWS::Region` などは、IAM のリソースを作る際には良く使うでしょう。

### !Sub を使おう

組み込み関数は次のように使います。Yamlの短縮形構文を使っています。

```yaml
!Sub "${NamePrefix}-ec2"
```

この関数は、`Prefix` というパラメータの値を代入した文字列を生成します。
次のTemplateは、EC2を作るだけの単純なものです。

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Parameters:
  NamePrefix:
    Type: String
    Description: Name tag prefix
    MinLength: 1
    Default: myapp
  InstanceType:
    Type: String
    Description: EC2 instance type
    MinLength: 1
    Default: t2.micro

Resources:
  MyInstance:
    Type: 'AWS::EC2::Instance'
    Properties:
      InstanceType: !Ref InstanceType
      ImageId: ami-4af5022c
      Tags:
        - Key: Name
          Value: !Sub "${NamePrefix}-ec2"
```

デフォルトのパラメータを使用した場合、 `!Sub "${NamePrefix}-ec2` は `Parameters` で定義した `NamePrefix` のデフォルト値を使用して `myapp-ec2` と文字列を返します。
このようなパラメータを使って文字列にする際は `!Sub` を使いましょう。 `!Sub` が使えるようになる前の古いドキュメントやスライドでは `!Join` を使う方法が紹介されているかもしれませんが、今なら `!Sub` です。

### Refと!Refなら!Refの方がおすすめ

少し蛇足的な内容ですが `!Ref InstanceType` は `Ref InstanceType` と書いても問題ありません。 `Ref` が関数名なので `!` がなくても関数を指定したことになるためです。しかし `!Ref` とすればYamlのタグ機能を使っているため、エディターによってはハイライトが付くようになります。ハイライトが付くと分かりやすいので、私は `!Ref` がおすすめです。

### 疑似パラメータは必ず使おう

たまに、疑似パラメータを知らず `MY_APP_AWS_REGION` などと自前の Parameter を用意してしまうケースを見かけますが、 `!Ref AWS::Region` とすれば一発なので不要です。同様に AWSアカウントId は `AWS::AccountId` が持っていますし、Stack名だって `AWS::StackName` で取得できます。
さらに `!Sub` と組み合わせること便利です。次の例は、IAM Role を作成するものです。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  OperationIamRole:
    Type: "AWS::IAM::Role"
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: "Allow"
            Principal:
              Service:
                - "ec2.amazonaws.com"
            Action:
              - "sts:AssumeRole"
      ManagedPolicyArns:
        - !Sub "arn:aws:iam::${AWS::AccountId}:policy/AmazonEC2FullAccess-201708310220-kiyo"
      RoleName: !Sub "${AWS::StackName}-ops-iam-role"
```

`!Sub "arn:aws:iam::${AWS::AccountId}:policy/AmazonEC2FullAccess-201708310220-kiyo"` や `!Sub "${AWS::StackName}-ops-iam-role"` のように、 `!Sub` と組み合わせることで簡単に文字列を定義することができています。`!Sub` は疑似パラメータも参照できるのです。

## Step1.4 親切なパラメータの定義をしよう

TBD

## Step1.5 Templateファイルをテストしよう

TBD

### aws cloudformation validation を実行しよう

TBD

### cfn-lint を実行しよう

TBD

# Step2 CloudFormation Stack を管理しよう

TBD

## Step2.1 AWS CLI でスタックの管理をしよう

TBD

### 最初はWebコンソールで流れをつかもう

TBD

### CLIで再現性の高い作業ができるようになろう

TBD

## Step2.2 Change Sets を使って更新前の確認をしよう

TBD

### 確認済みですぐに適用したい場合は deloy を使おう

TBD

### update-stack は使わないようにしよう

TBD

## Step2.3 通知を出そう

TBD

## Step2.4 CI/CDを回そう

TBD

### CI/CDを設計する

TBD

### CI用の環境を用意しておく

TBD

### GitHub + CircleCI の例

TBD

### CI用のStackを使って

TBD

# Step3 CloudFormation Template の再利用性を意識しよう

TBD

## Step3.1 Conditions と AWS::NoValue を活用して制御しよう

TBD

## Step3.2 CloudFormation cross stack reference を活用しよう

TBD

### 番外編: Conditions を使うべきか Template を分けるべきか

TBD

# 参考

- [AWSマイスターシリーズ AWS CloudFormation](https://www.slideshare.net/AmazonWebServicesJapan/aws-aws-cloudformation)
  - CloudFormationの仕組みはこれを見ればだいたい分かる
- [AWS Black Belt Online Seminar 2016 AWS CloudFormation](https://www.slideshare.net/AmazonWebServicesJapan/aws-black-belt-online-seminar-2016-aws-cloudformation)
  - 2016/12に公開された資料。一番新しいノウハウが詰まった公式スライド。
- [AWS CloudFormation のベストプラクティス](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/best-practices.html)
  - スライド版 [AWS CloudFormation Best Practices](https://www.slideshare.net/AmazonWebServices/aws-cloudformation-best-practices)
  - CloudFormationを運用する際のベストプラクティス
