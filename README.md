# Traffic Lights

I wanted to make it _really_ clear when my builds are broken, so I hooked up a decomissioned & refurbished set of London traffic lights to a [Spark Core](https://www.particle.io/prototype) and built this small ruby web app to redirect travis build push events to it via the Particle API.

These devices are very low powered, so this webapp translates Travis' [webhook notifications](http://docs.travis-ci.com/user/notifications/#Webhook-notification) into the simple POST request required by the [Core API](http://docs.particle.io/core/api/).

## Set up your repo

You'll need to configure Travis so that it talks to your traffic light controller app. Add the following lines to your `.travis.yml`:

```yaml
notifications:
  webhooks:
    urls:
      - http://traffic.byjp.me/travis?<your-spark-device-id>
    on_success: always
    on_failure: always
    on_start: always
```

## Deploy the web app

You can find the code for this web application [on github](https://github.com/jphastings/traffic). It's being run on [Digital Ocean](https://www.digitalocean.com/) via [Tutum](https://tutum.co) (a truly splendid combination I should blog about) at http://traffic.byjp.me (though you'll have to deploy your own at the moment).

When you deploy make sure that you have environment variables set up for authentication, requests that don't authenticate correctly will be rejected, so only you can update your traffic lights:

```text
spark.<your-spark-device-id>=<your-spark-token>
travis.<your-repo-owner>=<your-travis-token-for-that-user>
```

## Bring your traffic lights online

Flash your spark with the following Processing code:

```processing
// Set your pins here
int lamp_g = D0;
int lamp_a = D2;
int lamp_r = D1;

void setup()
{
  pinMode(lamp_g, OUTPUT);
  pinMode(lamp_a, OUTPUT);
  pinMode(lamp_r, OUTPUT);
  Spark.function("traffic", lightsToggle);
  display(7);
}

void loop() {}

int display(int bits) {
  digitalWrite(lamp_g, bits & 1);
  digitalWrite(lamp_a, bits & 2);
  digitalWrite(lamp_r, bits & 4);
  return bits;
}

int lightsToggle(String status) {
  display(status.toInt());
  return 0;
}

```