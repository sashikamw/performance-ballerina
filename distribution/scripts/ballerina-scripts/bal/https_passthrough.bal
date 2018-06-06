import ballerina/http;

endpoint http:Listener passthroughEP {
    port:9090,
	secureSocket: {
        keyStore: {
          path: "${ballerina.home}/bre/security/ballerinaKeystore.p12",
            password: "ballerina"
        }
    }
};

endpoint http:Client nettyEP {
    url:"http://netty:8688"
};

@http:ServiceConfig {basePath:"/passthrough"}
service<http:Service> passthroughService bind passthroughEP {

    @http:ResourceConfig {
        methods:["POST"],
        path:"/"
    }
    passthrough (endpoint outboundEP, http:Request clientRequest) {
        var response = nettyEP -> forward("/service/EchoService", clientRequest);
        match response {
            http:Response httpResponse => {
                _ = outboundEP -> respond(httpResponse);
            }
            http:error err => {
                http:Response errorResponse = new;
                json errMsg = {"error":"error occurred while invoking the service"};
                errorResponse.setJsonPayload(errMsg);
                _ = outboundEP -> respond(errorResponse);
            }
        }
    }
}

