# Kong OpenWhisk Plugin

This plugin invokes
[OpenWhisk Action](https://github.com/openwhisk/openwhisk/blob/master/docs/actions.md).
It can be used in combination with other request plugins to secure, manage
or extend the function.

## Table of Contents

- 1. [Usage][usage]
- 2. [Installation][installation]
- 3. [Configuration][configuration]
- 4. [Demonstration][demonstration]
- 5. [Limitations][limitations]

[usage]: #1-usage
[installation]: #2-installation
[configuration]: #3-configuration
[demonstration]: #4-demonstration
[limitations]: #5-limitations

## 1. Usage

This plugin will make Kong collect all the parameters from incoming requests,
invoke the configured OpenWhisk Action, and send the response to downstream.

[Back to TOC](#table-of-contents)

## 2. Installation

To install this plugin (and be able to configure it via the Kong Admin API),
follow the instructions in the provided INSTALL.txt file.

You must do so for every node in your Kong cluster. See the section about using
LuaRocks behind a proxy if necessary, in the INSTALL.txt file.


[Back to TOC](#table-of-contents)

## 3. Configuration

Method 1: apply it on top of an API by executing the following request on your
Kong server:

```bash
$ curl -X POST http://kong:8001/apis/{api}/plugins \
    --data "name=openwhisk" \
    --data "config.host=OPENWHISK_HOST" \
    --data "config.service_token=AUTHENTICATION_TOKEN" \
    --data "config.action=ACTION_NAME" \
    --data "config.path=PATH_TO_ACTION"
```

Method 2: apply it globally (on all APIs) by executing the following request on
your Kong server:

```bash
$ curl -X POST http://kong:8001/plugins \
    --data "name=openwhisk" \
    --data "config.host=OPENWHISK_HOST" \
    --data "config.service_token=AUTHENTICATION_TOKEN" \
    --data "config.action=ACTION_NAME" \
    --data "config.path=PATH_TO_ACTION"
```

`api`: The `id` or `name` of the API that this plugin configuration will target

Please read the [Plugin Reference](https://getkong.org/docs/latest/admin-api/#add-plugin)
for more information.

Attribute                                | Description
----------------------------------------:| -----------
`name`                                   | The name of the plugin to use, in this case: `openwhisk`
`config.host`                            | Host of the OpenWhisk server.
`config.port`<br>*optional*              | Port of the OpenWhisk server. Defaults to `443`.
`config.path`                            | The path to the `Action` resource.
`config.action`                          | Name of the `Action` to be invoked by the plugin.
`config.service_token`<br>*optional*     | The service token to access Openwhisk resources.
`config.https_verify`<br>*optional*      | Set it to true to authenticate Openwhisk server. Defaults to `false`.
`config.https`<br>*optional*             | Use of HTTPS to connect with the OpenWhisk server. Defaults to `true`.
`config.timeout`<br>*optional*           | Timeout in milliseconds before aborting a connection to OpenWhisk server. Defaults to `60000`.
`config.result`<br>*optional*            | Return only the result of the `Action` invoked. Defaults to `true`.
`config.keepalive`<br>*optional*         | Time in milliseconds for which an idle connection to OpenWhisk server will live before being closed. Defaults to `60000`.

Note: If `config.https_verify` is set as `true` then the server certificate
will be verified according to the CA certificates specified by the
`lua_ssl_trusted_certificate` directive in your Kong configuration.

[Back to TOC](#table-of-contents)

## 4. Demonstration

For this demonstration we are running Kong and 
[Openwhisk platform](https://github.com/openwhisk/openwhisk) locally on a
Vagrant machine on a MacOS.

1. Create a javascript Action `hello` with the following code snippet on the
Openwhisk platform using [`wsk cli`](https://github.com/openwhisk/openwhisk-cli).

    ```javascript
    function main(params) {
        var name = params.name || 'World';
        return {payload:  'Hello, ' + name + '!'};
    }
    ```

    ```bash
    $ wsk action create hello hello.js

    ok: created action hello
    ```

2. Create an API on Kong

    ```bash
    $ curl -i -X  POST http://localhost:8001/apis/ \
      --data "name=openwhisk-test" -d "hosts=example.com" \
      --data "upstream_url=http://localhost"

    HTTP/1.1 201 Created
    ...

    ```

3. Apply the `openwhisk` plugin to the API on Kong

    ```bash
    $ curl -i -X POST http://localhost:8001/apis/openwhisk-test/plugins \
        --data "name=openwhisk" \
        --data "config.host=192.168.33.13" \
        --data "config.service_token=username:key" \
        --data "config.action=hello" \
        --data "config.path=/api/v1/namespaces/guest"

    HTTP/1.1 201 Created
    ...

    ```

4. Make a request to invoke the Action

    **Without parameters**

      ```bash
      $ curl -i -X POST http://localhost:8000/ -H "Host:hello.com"
      HTTP/1.1 200 OK
      ...

      {
        "payload": "Hello, World!"
      }
      ```

    **Parameters as form-urlencoded**

      ```bash
      $ curl -i -X POST http://localhost:8000/ -H "Host:hello.com" --data "name=bar"
      HTTP/1.1 200 OK
      ...

      {
        "payload": "Hello, bar!"
      }
      ```

    **Parameters as JSON body**

      ```bash
      $ curl -i -X POST http://localhost:8000/ -H "Host:hello.com" \
        -H "Content-Type:application/json" --data '{"name":"bar"}'
      HTTP/1.1 200 OK
      ...

      {
        "payload": "Hello, bar!"
      }
      ```

    **Parameters as multipart form**

      ```bash
      $ curl -i -X POST http://localhost:8000/ -H "Host:hello.com"  -F name=bar
      HTTP/1.1 100 Continue

      HTTP/1.1 200 OK
      ...

      {
        "payload": "Hello, bar!"
      }
      ```

    **Parameters as querystring**

      ```bash
      $ curl -i -X POST http://localhost:8000/?name=foo -H "Host:hello.com"
      HTTP/1.1 200 OK
      ...

      {
        "payload": "Hello, foo!"
      }
      ```

    **OpenWhisk metadata in response**
    
      When Kong's `config.result` is set to false, OpenWhisk's metadata will be returned in response:
    
      ```bash
      $ curl -i -X POST http://localhost:8000/?name=foo -H "Host:hello.com"
      HTTP/1.1 200 OK
      ...

      {
        "duration": 4,
        "name": "hello",
        "subject": "guest",
        "activationId": "50218ff03f494f62abbde5dfd2fcc68a",
        "publish": false,
        "annotations": [{
          "key": "limits",
          "value": {
            "timeout": 60000,
            "memory": 256,
            "logs": 10
          }
        }, {
          "key": "path",
          "value": "guest/hello"
        }],
        "version": "0.0.4",
        "response": {
          "result": {
            "payload": "Hello, foo!"
          },
          "success": true,
          "status": "success"
        },
        "end": 1491855076125,
        "logs": [],
        "start": 1491855076121,
        "namespace": "guest"
      }
      ```

[Back to TOC](#table-of-contents)

## 5. Limitations

**Use a fake upstream_url**:

When using the this plugin, the response will be returned by the plugin itself
without proxying the request to any upstream service. This means that whatever
`upstream_url` has been set on the [API](https://getkong.org/docs/latest/admin-api/#api-object)
it will never be used. Although `upstream_url` will never be used, it's
currently a mandatory field in Kong's data model, so feel free to set a fake
value (ie, `http://localhost`) if you are planning to use this plugin.
In the future, we will provide a more intuitive way to deal with similar use cases.

**Response plugins**:

There is a known limitation in the system that prevents some response plugins
from being executed. We are planning to remove this limitation in the future.

[Back to TOC](#table-of-contents)
