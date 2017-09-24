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

## Step2.4 CI/CDで自動化しよう

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
- [CloudFormationのリリース履歴](http://docs.aws.amazon.com/ja_jp/AWSCloudFormation/latest/UserGuide/ReleaseHistory.html)
