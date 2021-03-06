import ballerina/http;

endpoint http:Listener passthroughEP {
    port:9090
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
    passthrough (endpoint outboundEP, http:Request req) {
	json payload = req.getJsonPayload() but {error => {}};
        xml xmlPayload = check payload.toXML({});
	http:Request clinetreq = new;
        clinetreq.setXmlPayload(xmlPayload);

        var response = nettyEP -> post("/service/EchoService", request = clinetreq);
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

