# 概要

本記事では私なりの CloudFormation を少しでも楽にメンテするノウハウを説明します。

## この記事で触れること

- [AWS CloudFormation](https://aws.amazon.com/jp/cloudformation/) の (私なりの) 作成・メンテ手順
	- Templateファイルをどうやって書くか
	- スタックの作成、更新手順
	- テスト・CI・動作確認の流れ
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
	- 私にはベストプラクティスを説明できる自信がないので省いています[^1]
- [CloudFormation StackSets](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- CloudFormationを操作する権限管理
  - 例えば、CloudFormationの操作はしても良いけど、EC2やS3などには直接触ってほしくない場合のIAM設定方法
  - IAM設計が絡むと本記事では扱いきれないので触れません
- 代替ツールとの比較
  - [Terraform](https://www.terraform.io/) や `awscli` 以外のCLIツールには触れません

[^1]: ヘルパースクリプトはなるべく使わない方が良いと考えています。数年前ならともかく、今なら代替手段があるはずです。

# 前章. CloudFormation を使う必要はあるのか

この記事を読もうと思った方は、少なくとも AWS CloudFormation という仕組みの存在を知っていることでしょう。
中には、CloudFormationの作成に試行錯誤中の方や、Stackの管理で困っている方、あるいは CloudFormation を止めたくてたまらないという方もいることでしょう。
AWS CloudFormationは巨大なツールです。今日明日で使い方を身につけることは難しく、かりにマスターしたとしても、テンプレートファイルを読んだだけでリソース構成を全て理解できるなどという日は永遠に訪れないでしょう。
それなのに、なぜ CloudFormation が必要なのでしょうか。
一つの答えは、世の中にある別のツールが持っています。AWS ElasticBeanstalk を使ったことはあるでしょうか？ もしくは awsecscli を使って ECS クラスターを作ったことはあるでしょうか？ Serverless コマンドを触ったことは？ TBD は？
これらのツールは内部でCloudFormationを活用しています。AWSのリソースを必要なだけ作成し・更新し・管理をまとめて行うには CloudFormation はうってつけです。

では私たちが私たちのためにCloudFormationを利用する必要はあるのでしょうか。
私の答えは「必要だ。だが昔ほどではない」です。
例えば AWS Lambda の管理のために CloudFormation を使用する必要はないでしょう。ServerlessやApexなど便利なツールが揃っています。こちらを活用したほうが圧倒的に管理が簡単です。
しかし VPC の構築やIAM設計やRDSの設定管理などは、CloudFormation を使った方が良いでしょう。どのSubnetとSubnetが接続できるのか、IAM Policyがどのような内容になっているのか、RDSの設定を何にしているのか、といった情報を知りたくなる度にWebコンソール画面で探すよりも、たった一つのCloudFormation Stackを確認すれば済む、という文化の方が効率的なのは明らかです。

あらゆるプログラミング言語や開発ツールがそうであるように、CloudFormationを使うタイミングもまた適材適所となるのです。

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
そして、もう１つが、CloudFormation Templateは設計図であり、その設計図は他の設計図となるべく疎結合にしておいた方が、内容の把握・修正が容易になると考えているためです。設計図の組み方やいつものフレーズなどを過去から使いまわすのは良いですが、ある設計図を変更したら別の設計図にも影響が出た、というのは避けるべきです。プログラミングならば、疎結合にしつつ共通化するようデザインするよう考えるところですが、CloudFormationでそこまでするメリットが果たしてあるのか悩ましいところです。共通化するに越したことはないが頑張ってやるほどでもない、というのが私の考えです。  

そのため、Templateファイルは多少同じような記述があってもダブルメンテ覚悟で管理し、代わりにツールを駆使してメンテ漏れに気付ける工夫をする方にコストを割くようにしています。  

次の例は、ec2.template.yaml は ci 環境用のParameterを許可しているか確認する簡単なスクリプトです。

```bash
$ ruby -ryaml -e 'raise "should be allowed ci environment" unless YAML.load_file(ARGV[0])["Parameters"]["Environment"]["AllowedValues"].include?("ci")' ec2.template.yaml
-e:1:in `<main>': should be allowed ci environment (RuntimeError)
```

こうしておけば、サービスの規模が大きくなってCloudFormationの共通部分が肥大化したのでいい加減まとめたくなった時にも、このテストを流して確認しながら移行することが可能になります。[^5]

結局、プログラムでテストしてるじゃないか、という指摘を受けるかもしれませんが、Yamlをカスタムできる仕組みを自分たちで作ることと、Yamlの記述内容をテストするスクリプトを書くことでは、後者の方が敷居が低く取り入れやすいと思うのです。

[^4]: 実際にCloudFormationの共通化をしたことがあるのですが、どこまでを共通化するか、共通化の仕組み・仕様はどんなか、共通化よるデグレなどがないか確認する方法、それらのドキュメント整備など作業が多く、費用対効果が適切ではないと感じました。ただ、共通化の仕組み自体は既存のツールを組み合わせればそれほどコストが掛からないと思うので、いずれ私の意見は変わる可能性があります。
[^5]: 移行前後のTemplateで diff を取る方が確実ですが

ちなみに、Templateの中でStackを作成することもできます。[^6]
Stackのネストです。作成するリソースの共通化として検討できると思いますが、私はStackの管理が難しくなるような気がして使っていません。特に、複数の親Stackから使われるTemplateファイルの管理が複雑になりそうです。

[^6]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/quickref-cloudformation.html

### Yamlの短縮形構文を使おう

TBD

## Step1.2 CloudFormation Designer を使おう

AWS CloudFormation Designer は 2015/10 から使えるようになった機能です。CloudFormation の Template の内容を理解するために、これほど便利な機能はありません。ぜひ活用しましょう。
実際に、私はこの機能を愛用しています。CloudFormation Designer がリリースされるまで、このTemplateが作るAWSリソース群の設計図を出力できたら良いのに、と何度思ったことか。
CloudFormation でできることは、言ってしまえば、AWS のリソースを作ることと、作ったリソースとリソースを関連付けることです。特に、リソースとリソースを関連付けていくと、Templateファイルは複雑化し、どのリソースがどこに依存しているのか追いかけるのが大変です。しかし CloudFormation Designer を使えば Template ファイル内で定義したリソースの関係がGUIで確認できるようになります。

AWS CloudFormation Designer は既存のTemplateを理解するためだけでなく、新しいTemplateファイルを作成する時にも使えます。CloudFormationに慣れていない方は、いきなりテキストエディターを開かず、AWS CloudFormation Designer を使ってTemplateファイルを作ったほうが楽かもしれません。AWS CloudFormation Designer は補完機能も備えているので、それなりに快適な作業ができます。

一方で AWS CloudFormation Designer を使うと、 `Metadata` という情報が Template ファイルに追加されてしまいます。これは、Designer上のリソースの表示位置を保持していて、ちょっと位置を変えただけで `Metadata` が変化するため、バージョン管理ツールを使っていると差分として出てきてしまいます。「この差分は何だっけ...ああ Metadata か」という無駄な作業はしたくありません。その為私は、Templateの構成理解のために Designer を使いTemplateファイルの作成や修正自体は手慣れたツールで行う、という方針にしています。

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

[^6]: 2016/09に追加された関数です。参考) https://aws.amazon.com/jp/blogs/aws/aws-cloudformation-update-yaml-cross-stack-references-simplified-substitution/

#### 疑似パラメータ

疑似パラメータ[^5] は、たとえるならCloudFormationが持つグローバル変数のようなものです。どのCloudFormationでも、特に何の前準備も無しに参照できるパラメータです。  
現時点では次の5種類が使えます。

[^5]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/pseudo-parameter-reference.html

- `AWS::AccountId`
  - AWSアカウントIdを取得する
- `AWS::NotificationARNs`
  - Stackの通知を受け取るArn
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

この関数は、`NamePrefix` というパラメータの値を代入した文字列を生成します。
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

### Ref:と!Refなら!Refの方がおすすめ

少し蛇足的な内容ですが `!Ref InstanceType` は `Ref: InstanceType` と書いても問題ありません。しかし `!Ref` とすればYamlのタグ機能を使っているため、エディターによってはハイライトが付くようになります。`Ref:` だとYamlのキーとしてのハイライトとなり、他のキーに埋もれてしまいますが、 `!Ref` ならAWSの関数を使っているとすぐに分かるので `!Ref` をおすすめします。

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

CloudFormation のパラメータはできるだけ使う人のことを考えて設定しましょう。
他の値は Template を作る人しか使いませんが、パラメータはTemplateを使う人も指定するからです。
不親切なパラメータでは「このParameterは何を指定すれば良いんですか？」と質問され、挙げ句の果てには「お願いします」と投げられてしまうかもしれません。

プログラマーの間では、型は最低限のドキュメント、という認識があったりなかったりします。ある関数の引数と戻り値の型が明確になっていれば、その型を使えば良いのだとすぐに分かります。
同じように、パラメータの型をできるだけ想定しているものに沿うよう定義すれば、それだけで利用者に情報を与えることができます。

では、どのようにしてパラメータの型を定義するか、いくつか例をピックアップして説明しましょう。

### AWS 固有のパラメーター型

AWS固有のパラメーター型[^1]が使える場合は必ず使いましょう。非常に有効です。
例えば `AWS::EC2::Instance::Id` という型を使うと、InstanceId しか指定できないパラメーターを定義できます。強力なのは、Stackを作ろうとしているAWSアカウント上に存在していないIdを指定すると、即座にエラーとなる点です。利用者はすぐに「あ、このId間違ってた」と気付くことができます。

[^1]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html の後半を参照

### AllowedPattern

AWS 固有のパラメーター型が使えない場合、基本的にはこの `AllowedPattern` を使うことになります。
パラメーターが取りうる文字列を正規表現で定義します。
正規表現が得意ではない方のために、よく使いそうなものをリストアップしておきました。
なお `AllowedPattern` を使う時は同時に `ConstraintDescription` を使うと親切です。


TBD: AllowedPattern

```yaml
AllowedPattern: 
ConstraintDescription: 
```

## Step1.5 Templateファイルをテストしよう

私は、CloudFormationは学習コストが高い仕組みだと思います。独自の記法・仕組みが多く、それらを把握するにはドキュメントを読みながら試すしかありません。しかし実際にTemplateファイルを書いて、試して、失敗したStackを削除して、という作業を繰り返すのは手間ですし、精神的にも辛い作業です。
特に単純なケアレスミスは、Stackを作る前に気付きたいものです。
「何で失敗したんだろう」
「あ、タイプミスか...」
そんな虚無感を味合う前に、次のようなツールを使ってTemplateをテストしましょう。

### aws cloudformation validate-template を実行しよう

`aws-cli` をインストールしていれば使えるコマンドです。
`aws-cli` はAWS公式のツールですので、使わない手はありません。後述するStackの管理にも使います。

使い方は簡単です。

例えばここに、`Type` を `Typo` に typo したTemplateファイルを用意しました。

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Resources:
  S3Bucket:
    Typo: 'AWS::S3::Bucket'
    Properties:
      LifecycleConfiguration:
        Rules:
          - Status: Enabled
            ExpirationInDays: 1
```

この Template に CLI で vaildation を実行すると「`Type` が必須だよ！」と怒ってくれます。

```bash
$ aws cloudformation validate-template --template-body file://./step5/invalid.template.yaml

An error occurred (ValidationError) when calling the ValidateTemplate operation: Template format error: [/Resources/S3Bucket] Every Resources object must contain a Type member.
```

実はこの validation は Stack を作成する時にも事前に自動で実行されるので、わざわざ実行しなくても良いと思うかもしれません。
しかし、コマンドを実行してすぐにエラーを教えてくれるのと、Stack名やパラメータを入力してからよし実行だ、としてからエラーとなるのとでは、徒労感が全く違うでしょう。

ただし、このツールには大きな欠点があります。
次のTemplateファイルはミスがあり、Stackが作成できません。

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Resources:
  S3Bucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      LifecycleConfiguration:
        Rule:
          - Status: Enabled
            ExpirationInDays: 1
```

しかし validaion は成功してしまいます。

```bash
$ aws cloudformation validate-template --template-body file://./step5/invalid.template.yaml
{
    "Parameters": []
}
```

`aws cloudformation validate-template` は力不足で CloudFormation Template の Format が正しいかどうかの検証はしてくれるのですが、必須ではないパラメータやその値が正しいかどうかはチェックしてくれないのです。
何がミスなのかは次の章で説明しましょう。

### cfn-lint を実行しよう

[cfn-lint](https://github.com/martysweet/cfn-lint) という便利なツールがあります。
Node.jsで動いていますので `npm install -g cfn-lint` などとしてインストールしましょう。

このツールを使って、上記で例示したミスを含むTemplateの検証をしてみます。

```bash
$ cfn-lint validate step5/invalid.template.yaml
0 infos
0 warn
2 crit
Resource: Resources > S3Bucket > Properties > LifecycleConfiguration
Message: Required property Rules missing for type AWS::S3::Bucket.LifecycleConfiguration
Documentation: http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-s3-bucket-lifecycleconfig.html, http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-s3-bucket.html#cfn-s3-bucket-lifecycleconfig

Resource: Resources > S3Bucket > Properties > LifecycleConfiguration
Message: Rule is not a valid property of AWS::S3::Bucket.LifecycleConfiguration
Documentation: http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-s3-bucket-lifecycleconfig.html, http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-s3-bucket.html#cfn-s3-bucket-lifecycleconfig

Template invalid!
```

何やらメッセージが出てきました。
ミスの内容は `Rules` とすべきところを `Rule` と書いていた、なのですが、 `cfn-lint` は見事にそれを `Rules` が無い・`Rule` なんてプロパティは存在しない、と指摘してくれています。ありがたいですね。

さらに `cfn-lint` はおまけで `cfn-lint docs` というコマンドを用意しています。
例えば `cfn-lint docs AWS::S3::Bucket.LifecycleConfiguration` と実行すると、ブラウザでS3 Bucket LifecycleConfiguration のCloudFormationに関するドキュメントを開いてくれます。いちいち検索しなくて済むので便利です。

# Step2 CloudFormation Stack を管理しよう

Step1 では CloudFormation Template の書き方について触れました。
ここからは Template を使って CloudFormation Stack を作成・更新・運用していくための Tips となります。

Stack の管理は、次の点さえ気をつけていれば難しくはありません。

- パラメーターの指定ミスに注意する
- Stackの依存関係に注意する
- Stackを更新した時のリソース置き換えに注意する

## Step2.1 AWS CLI でスタックの管理をしよう

CloudFormation Stack の作成・更新・削除をする方法はいくつか方法があります。

1. AWS Web コンソール画面で作業する
1. `awscli` を使ってCLIで作業する
1. 外部サービスを利用する

ここでは `awscli` に絞って解説します。[^1]

[^1]: 執筆時の `awscli` の version は `aws-cli/1.11.162` です

### 最初はWebコンソールで流れをつかもう

CloudFormationを触り始めた頃はWebコンソールで作業をしましょう。
この時、できれば英語表記を使うことをおすすめします。`awscli` で使用するコマンドやオプションは英語なので、その英語が何を指すのか少しでも理解するためです。[^1]

[^1]: 余談ですが、私はWebコンソールを常に英語で使用しています。`awscli` をベースにしているため、日本語だとかえって何の機能か分からないことが多いのです。

ここでWebコンソールの使い方の解説は省略します。WebコンソールのUIは度々変わるので、キャプチャ画像にあまり意味はないと思います。
代わりに、どういった機能を触り、把握しておけば良いかリストアップしておきます。

- Stackの作成・削除
  - CloudFormation Template ファイルは Local PC 上と S3 上から選択できること
  - Template, Parameter の他に何やら設定できるものがあるということ
    - どちらかというとAWSの権限管理者向けの設定です
    - ※ 本記事ではあまり触れません
- Stackの更新
  - Stack 更新には ChangeSet という更新前後の差分を管理する仕組みがあるということ

### CLIで再現性の高い作業ができるようになろう

CloudFormationの流れを掴めたら次は CLI を使っていきましょう。
言わずもがなですが、Webページでの作業は反復作業に向いていません。かといって自前でプログラムを作るのは費用対効果として見合わない場合もあるでしょう。[^1]
そこで `awscli` です。すでにご存知かもしれませんが `awscli` はAWSの各種サービス用APIをラップしてCLIツールに仕上げたもので、AWSのWebコンソールで行っていることは、ほぼ全て `awscli` で代替可能です。中にはWebコンソールでは処理できないものすらあるので、AWSを運用するなら必須と言っても良いツールでしょう。

[^1]: ちょっとしたツールのつもりでも継続的なメンテと拡張性を...と考えると、それなりに工数がかかるものです

`awscli` のインストール方法は割愛します。[^1]
`aws cloudformation help` を実行すると使用できるコマンドが分かります。執筆時時点では 44 のコマンドが使えるようです。
いきなり44つ全てのコマンドを把握して使いこなすのは時間がかかるので、私がよく使用するコマンドをリストアップしておきます。

[^1]: awscliのインストール方法は http://docs.aws.amazon.com/ja_jp/cli/latest/userguide/installing.html を参考

- create-stack
  - stack を作成する
- wait stack-create-complete
  - stack の作成が完了するまで待つ
- create-change-set
  - change-set を作成する
  - 詳しくは後述します
- wait change-set-create-complete
  - change-set の作成が完了するまで待つ
- execute-change-set
  - change-set を適用する
- wait stack-update-complete
  - change-set の適用 = stack の更新が完了するまで待つ
- delete-stack
  - stack を削除する
- wait stack-delete-complete
  - stack の削除が完了するまで待つ

### 番外編: --generate-cli-skeleton を活用しよう

`awscli` には、私の知る限り全てのコマンドで `--generate-cli-skeleton` というオプションが使えます。
例えば `aws cloudformation create-stack --generate-cli-skeleton` を実行すると、次のような出力になります。

```bash
# 出力が長いので省略しています
$ aws cloudformation create-stack --generate-cli-skeleton
{
  "StackName": "",
  "TemplateBody": "",
  "TemplateURL": "",
  "Parameters": [
  {
    "ParameterKey": "",
    "ParameterValue": "",
    "UsePreviousValue": true
  }
  ],
  "DisableRollback": true,
以下略
```

これらのキーが、それぞれ `awscli` のオプションの1つ1つに紐付いています。
`StackName` は `--stack-name` に `TemplateBody` は `--template-body` に、といった具合です。
そして `--generate-cli-skeleton` と対をなす `--cli-input-json` を使うと、オプションを指定する代わりに json の値を読み込ませることができます。

例えば次のような json ファイルを用意して、

```json
{
  "StackName": "SampleStack",
  "TemplateBody": "file://sample.template",
  "Parameters": [{
    "ParameterKey": "Param",
    "ParameterValue": "foo"
  }],
  "Tags": [{
    "Key": "Env",
    "Value": "test"
  }]
}
```

次のようなコマンドを実行すると、

```bash
$ aws cloudformation create-stack --cli-input-json sample.json
```

必要なオプションを省略して stack を作成することができ、効率的に作業することができます。
特にCloudFormationでは `Parameters` の値を変えて構築することが多いのですが、パラメータをオプションで1つずつ指定するのは面倒なので、このようにファイルで管理する方が良いでしょう。

## Step2.2 Change Sets を使って更新前の確認をしよう

作った CloudFormation Stack は更新することができます。
Stack作成時に使った Template
CloudFormation の Stack 更新は Change Sets[^1] という仕組みを使います。
もはや、Change Sets を使わずにStackの更新をしようなんて今では考えられません。[^1]

[^1]: 日本語では変更セット、と表現されています
[^1]: この仕組みが入る前まで Stack の更新の前にどうやって確認していたか、もはや記憶にありません

### Change Sets を知ろう

Stackを更新したい時、最も気になるのは「更新して大丈夫なのか」という不安です。ひょっとすると、ちょっとした変更のつもりがEC2の再構築が実行されてしまいアラートが飛ぶ、想定外のリソースが削除されてしまってデータが飛ぶ、といった経験をしたことがあるせいかもしれません。
こうした不安を払拭するには、この Stack 更新 で何がどうなるのかを知る必要があります。
そして、そのための仕組みが Change Sets です。
Change Sets は、Stack 更新によって使用する Template ファイル

では、Change Sets の使い方を見ていきましょう。

### Change Sets を使おう

Change Sets の基本的な使い方の流れは次の通りです。

1. Change Sets を作る
1. 作った Change Sets の中身を確認する
1. Change Sets を実行する
1. Change Sets を削除する

Webコンソール上で行う方法は [AWS 公式ブログ](https://aws.amazon.com/jp/blogs/news/new-change-sets-for-aws-cloudformation/) で説明されているのでそちらを見てください。
ここでは aws-cli での手順を見てみましょう。

#### Change Sets を作る

Change Sets を作るコマンドは次のようなものです。

```bash
change_set_name="ChangeSet名" # ex) my-stack-20171111
template_file="Templateファイルパス"
input_json="Parameterを記述したjsonファイルパス"

aws cloudformation create-change-set \
  --change-set-name "${change_set_name}" \
  --template-body "file://${template_file}" \
  --cli-input-json "file://${input_json}" # input_json に stack名も書いているので --stack-name オプションは不要
```

このコマンドを実行するとすぐにレスポンスが返ってきます。
awscli を使ったことのある方はご存知だと思いますが、awcli では操作が完了するまで待たないコマンドが幾つかあります。
`create-change-set` もその１つで、ChangeSetsの作成を開始したことをレスポンスで返しますが、作成が完了したのかどうかは分かりません。

そこで `wait` コマンドを使うことになります。

```bash
aws cloudformation wait change-set-create-complete \
  --change-set-name "${change_set_name}" \
  --stack-name "${stack_name}"
```

ただし、このままだともし Change Sets の作成に失敗した時に「なぜ失敗したのか」が分かりません。
そこで `wait` が失敗した時に Change Sets の詳細を取得するようにしましょう。

```bash
aws cloudformation wait change-set-create-complete \
  --change-set-name "${change_set_name}" \
  --stack-name "${stack_name}" || {
    aws $(fn::aws_option) cloudformation describe-change-set \
      --change-set-name "${change_set_name}" \
      --stack-name "${stack_name}"
    exit 1
  }
```

#### 作った Change Sets の中身を確認する

Change Sets の中身を確認するコマンドは次のようなものです。

```bash
change_set_name="ChangeSet名" # ex) my-stack-20171111
input_json="Parameterを記述したjsonファイルパス"

aws cloudformation describe-change-set \
  --change-set-name "${change_set_name}" \
  --cli-input-json "file://${input_json}" # input_json に stack名も書いているので --stack-name オプションは不要
```

TBD

#### Change Sets を実行する & Change Sets を削除する

Change Sets を実行する、すなわち Stack を更新するコマンドは次のようなものです。

```bash
change_set_name="ChangeSet名" # ex) my-stack-20171111
input_json="Parameterを記述したjsonファイルパス"

aws cloudformation execute-change-set \
  --change-set-name "${change_set_name}" \
  --cli-input-json "file://${input_json}" # input_json に stack名も書いているので --stack-name オプションは不要
```

Change Sets を作る時と同様に、このコマンドを実行するとすぐにレスポンスが返ってきます。
これでは Change Sets が成功したのか失敗したのか分からないので、 `wait` コマンドを使いましょう。

```bash
aws cloudformation wait stack-update-complete --stack-name "${stack_name}"
```

更新が失敗したら、なぜ失敗したのか知りたいので、コマンドを繋げて更新時のイベントを確認しましょう。

```bash
aws cloudformation wait stack-update-complete --stack-name "${stack_name}" || {
  aws $(fn::aws_option) cloudformation describe-stack-events --stack-name "${stack_name}"
  exit 1
}
```

### 確認済みですぐに適用したい場合は deloy を使おう

何が更新されるかは分かっているのですぐに反映させたい、という時に使うことができるコマンドは2種類あります。

- `aws cloudformation deploy`
  - ChangeSetの作成・実行をまとめて行う
- `aws cloudformation update-stack`
  - ChangeSetを作成せずStackを直接更新する

どちらを使うべきか、という話になりますが、特に理由が無ければ `aws cloudformation deploy` を使う方が良いでしょう。

```bash
change_set_name="ChangeSet名" # ex) my-stack-20171111
template_file="Templateファイルパス"
input_json="Parameterを記述したjsonファイルパス"

aws cloudformation deploy \
  --template-file "${template_file}" \ # file:// は不要です
  --cli-input-json "file://${input_json}" # input_json に stack名も書いているので --stack-name オプションは不要
```

`update-stack` は Change Sets の仕組みが生まれる前から存在するコマンドです。
`deploy` の方が新しいから良い、というわけではありませんが、`deploy` は Change Sets の仕組みを使っているため、Change Sets の作成に成功するか、というチェックが必然的に行われることになります。これにより、テンプレートファイルのフォーマットエラーやパラメータの不整合など、Stackを更新する前に気付けるミスを先に検出することができます。 `update-stack` では、即座にStackの更新が始まってしまうため、些細なミスでも Stack Rollback が実行される可能性があります。

では、`update-stack` はもう使われることのないコマンドなのかというと、そうではありません。
Stack で管理されているリソースの更新は `deploy` を使う方が好ましいですが、Stack 自体の設定、例えば Stack Policy や Rollback Policy などは `update-stack` を使う必要があります。
`update-stack` が受け持っていた多くの役割のうち、Stack内で管理するリソースの追加・更新・削除は `deploy` に委譲されたものとして考えると良いでしょう。

TODO: 動作確認する

## Step2.3 通知を出そう

Stack の操作が完了するには時間がかかります。その間にコーヒーを飲んで一息入れるのがベストな選択ですが、うっかり猫動画を見てしまい、うっとりしているうちにStackの作成が完了していた、なんてことが良くあります。
そうならないよう、Stack の操作が完了したらすぐに次の作業に移れるようにしましょう。
まさか、定期的にブラウザをF5して確認なんてしてませんよね？

### CloudFormation の Notifications を設定する

CloudFormation には Notifications という設定があります。
これは AWS SNS と連携するもので、Web コンソールだと SNS の作成自体もポチポチするだけで行なえます。
デフォルトはメール送信ですが、AWS SNS なのでカスタムは色々とできます。
鉄板なのは、AWS SNS から AWS Lambda を起動して Slack に通知する、といったものでしょうか。

### [macOS 向け] terminal-notifier コマンドを活用する

私が普段から便利に使っている `terminal-notifier` というツールがあります。
実行時間の長いコマンドが終わったら、Mac の通知として知らせてくれます。これが大変便利で、CloudFormation の Stack 操作以外にも、ちょっと重いテストを流した時やビルドに時間が掛かりそうだからその間に別の作業するか、ということが気軽にできるようになりました。
詳しくは [Macで時間のかかるコマンドが終わったら、自動で通知するzsh設定](https://qiita.com/kei_s/items/96ee6929013f587b5878) をご参考ください。

## Step2.4 CI/CDで自動化しよう

多くのソフトウエア開発がそうであるように、CloudFormation もまた CI/CD をすることができます。
CloudFormation にそんなものが必要か？ と思う方もいるかもしれませんが、むしろ CloudFormation だからこそ CI/CD が効果的なのです。
Step2.3 で ChangeSets の機能について触れましたが、これはまさに CloudFormation で CI/CD をするメリットの一つです。
Templateを修正し、レビューを経てマージされると実際にTemplateを適用し、Stackが意図通り作成・更新されることを確認する。こういった作業を気軽にできる環境があると、どれほど気が楽なことか。

### CI/CDを設計する

CI/CD とは言いましたが、具体的に何をするのかは述べていませんでした。
ここではまず、CloudFormation の CI/CD として想定される内容を洗い出してみましょう。

- CI
  - Templateファイルに誤りがないか検証する
  - Templateファイルの記述方法に不要な記述がないか検証する
  - Templateファイルにチームの方針に合わない記述がないか検証する
- CD
  - Stackの作成ができるか検証する
  - Stackの更新ができるか検証する
  - Stackの更新内容が想定通りか検証する
  - 必要に応じて、Stackと関連する別のテストを実行し、問題がないか検証する

もっと他にも考えることができるかもしれません。
思いつく限りできそうな事を洗い出して、どこまでやれば効果的か考えましょう。

例えば私の場合、複数人でCloudFormation Templateを触ることを考えると、CI の部分は重点的に取り組みたいところです。
人力ではコストが掛かるばかりなので、何かしらツールを使うか作るかして自動化するのは必須でしょう。
`aws cloudformation validate-template` はもちろん `cfn-lint` も活用できるでしょう。
一方で、CD はそれほど目くじらを立てなくても良いかもしれません。
事前にChangeSetsを作って、更新内容を確認さえしていれば、あとはレビューで良しと見なしてどんどんStackに反映させてしまいます。
`awspec` を使って Stack 作成後にAWSのリソースをチェックするかどうかは悩みます。SecurityGroup や BucketPolicy といった、セキュリティ的に気をつけたい部分はテストしたいところですが、他の内容は CloudFormation Template 自体をしっかりレビューしていれば十分だと思います。

### CI用の環境を用意しておく

TBD

### GitHub + CircleCI の例

TBD

### CI用のStackを使って

TBD

# Step3 CloudFormation Template の再利用性を意識しよう

Step1 では CloudFormatin Template の書き方、Step2 では CloudFormation Stack の作成・更新とCI/CDについて触れました。
ここまでくれば、CloudFormation を自由に使いこなし、気軽にメンテできる状態が整ったと言えるでしょう。
次は、どのような Template ファイルを書けばよいか、Template の設計についてとなります。ここが一番難しく、状況によって意見が変わる部分でもあるでしょう。

Templateファイルの設計についての、私の考えは「プログラマーの思想をなるべく流用する」を基本としています。
DRY とか テストしやすい実装をする方法とか、そういった思想です。
以降、私なりのTemplateの設計について述べていきます。

## Step3.1 どの程度の再利用性を求めるか決める

ゴールがなければ意識をしたところで底なし沼に落ちるだけなので、先に何かしら目標を立てましょう。
私の場合は「最低でもここまではやる」と「やるとしてもこれ以上はしない」の上限と下限を定めるようにしています。
例えば次のような感じです。

### 最低でもここまではやる

- `AWS::AccountId` と `AWS::Region` を使う
  - RegionはともかくAccountIdは普段覚えてないので、そもそも使わないと無理
- `develep` `test` `production` と環境が違っても同じTemplateが使えること
  - 環境ごとに使うTemplateが変わる -> 手順が変わる -> `production` への適用は実質ぶっつけ本番 -> 事故のもと
- Stackの依存関係が一直線になること
  - Stackの循環参照のような状態にならないこと

### やるとしてもこれ以上はしない

- Multi-Region 対応
  - 自分がメインで使っているRegion以外でも動くことを保証しようとしない、の意
    - サービスの規模的に必要ならばするが、必要でなければしない
    - 使いもしないRegionが使える・使えないを把握し続けるのは辛いので
- アプリケーションが違っても適用できるTemplateにすること
  - 頑張った結果、複雑なTemplateができるくらいなら分けてしまった方が良い
  - 共通する記述をどうしてもまとめたければ、Templateをビルドして生成するようなプログラマブルな仕組みを整える
    - 継承より委譲の考えと似ている

## Step3.2 Conditions と AWS::NoValue を活用して制御しよう

プログラム言語なら条件分岐で実装したくなるようなものを、CloudFormationでもやりたくなる時があります。
例えば「Production環境の時はこのリソースを作る」や「Auroraの`SnapshotIdentifier`が指定されていたら`MasterUsername`と`MasterUserPassword`」は無視する、といった具体です。
そんな時は `Conditions` や `AWS::NoValue` の出番です。

### Conditions

`Conditions` [^1] は CloudFormation のかなり初期の頃 [^1] から使うことができた機能です。
プログラミングに例えるなら、条件式の結果を保持する変数を定義しているようなものです。

```yaml
Conditions:
  IsProduction: !Equals [ !Ref Environment, "production" ]
```

と書けば、それは `IsProduction = (Environment == "")` といった処理となります。
重要なのは条件式で使うParameter (今回の例だと `Environment`) を定義しておく必要がある点です。つまり、 `Conditions` は `Parameters` で定義したパラメータを使用することが前提となります。

先程例えたとおり、`Conditions` は変数を保持するだけなので、他の箇所で使わなければ無駄になります。
`Conditions` で定義した変数の使い方は 2種類あります。

- `Resources` の `Conditions` パラメータで使う
- 条件関数 `!If` の第一引数で使う

[^1]: http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/conditions-section-structure.html
[^1]: リリース履歴によれば、少なくとも2013年11月には存在していたようです

#### `Resources` の `Conditions` パラメータで使う

これは、条件によってリソースを作る・作らないを制御したい時に活用します。
例えば、productionの時だけS3 Bucketを作る場合は次のように、S3BucketのResourceに`Conditions`で`IsProduction`を指定します。

```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues:
      - production
      - develop

Conditions:
  IsProduction: !Equals [ !Ref Environment, "production" ]

Resources:
  S3Bucket:
    Type: 'AWS::S3::Bucket'
    Conditions: IsProduction # ココ！
```

#### 条件関数 `!If` の第一引数で使う

こちらは、リソースを作るのは決まってるけど、プロパティの有無は条件によって変えたい場合に活用します。
例えば、productionの時だけS3のLifeCycleを有効にしたい場合は、次のような使い方になります。

```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues:
      - production
      - develop

Conditions:
  IsProduction: !Equals [ !Ref Environment, "production" ]

Resources:
  S3Bucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      LifecycleConfiguration:
        Rules:
          - Status: !If [ IsProduction, Enabled, Disabled ] # ココ！
            ExpirationInDays: 1
```

`!If` が三項演算子っぽい指定をすると思うと分かりやすいでしょう。

### AWS::NoValue

## Step3.3 CloudFormation cross stack reference を活用しよう

TBD

# 参考

- [AWSマイスターシリーズ AWS CloudFormation](https://www.slideshare.net/AmazonWebServicesJapan/aws-aws-cloudformation)
  - CloudFormationの仕組みはこれを見ればだいたい分かる
- [AWS Black Belt Online Seminar 2016 AWS CloudFormation](https://www.slideshare.net/AmazonWebServicesJapan/aws-black-belt-online-seminar-2016-aws-cloudformation)
  - 2016/12に公開された資料。一番新しいノウハウが詰まった公式スライド。
- [AWS CloudFormation のベストプラクティス](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/best-practices.html)
  - スライド版 [AWS CloudFormation Best Practices](https://www.slideshare.net/AmazonWebServices/aws-cloudformation-best-practices)
  - CloudFormationを運用する際のベストプラクティス
- [CloudFormationのリリース履歴](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/ReleaseHistory.html)
- [AWS公式テンプレートサンプル集](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-sample-templates.html)
