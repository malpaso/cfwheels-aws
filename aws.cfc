<cfcomponent displayname="AWS Plugin" output="false">
	<cffunction name="init" output="false">
        <cfscript>
            this.version = "1.1.7,1.1.8";

            //Clear out the application scope cache
            lock timeout="20" scope="application" {
            	application.aws = {};
            	application.aws.jars = 'lib/httpcore-4.2.jar,lib/httpclient-4.2.jar,lib/java-xmlbuilder-0.4.jar,lib/jets3t-0.9.0.jar';
            }

            return this;
        </cfscript>
    </cffunction>

    <cffunction name="s3ListObjects" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfscript>
    		return $getRestS3Service().listObjects(arguments.bucket);
    	</cfscript>
    </cffunction>

    <cffunction name="s3ListObjectsChunked" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfargument name="prefix" type="string" default="#$null()#"/>
    	<cfargument name="delimiter" type="string" default="#$null()#"/>
    	<cfargument name="maxListingLength" type="numeric" default="1000"/>
    	<cfargument name="priorLastKey" type="string" default="#$null()#"/>
    	<cfargument name="completeListing" type="boolean" default="false"/>
    	<cfargument name="return" type="string" default="objects"/>
    	<cfscript>
    		var loc = {};
    		loc.chunk = $getRestS3Service().listObjectsChunked(
    										arguments.bucket,
    										arguments.prefix,
    										arguments.delimiter,
    										arguments.maxListingLength,
    										arguments.priorLastKey,
    										arguments.completeListing
    									);
    		if(arguments.return == 'prefixes')
    			return loc.chunk.getCommonPrefixes();

    		return loc.chunk.getObjects();
    	</cfscript>
    </cffunction>

    <cffunction name="s3GetObjectHeads" returntype="any" output="false">
    	<cfargument name="bucket" type="string" required="true"/>
    	<cfargument name="objects" type="any" required="true"/>
    	<cfscript>
    		return $getThreadedService().getObjectsHeads(arguments.bucket,arguments.objects);
    	</cfscript>
    </cffunction>

    <cffunction name="s3DownloadObjects" returntype="any" output="false">
        <cfargument name="bucket" type="string" required="true"/>
        <cfargument name="objects" type="any" required="true"/>
        <cfscript>
            var loc = {};

            loc.objectsLength = arrayLen(arguments.objects);
            loc.downloadPackageClass = $createJavaObject('org.jets3t.service.multi.DownloadPackage');
            loc.array = $createJavaObject('java.lang.reflect.Array');
            loc.downloadPackages = loc.array.newInstance(loc.downloadPackageClass.getClass(), loc.objectsLength);

            loc.returnValue = [];

            //Make downloadpackage objects for each key in the keys array
            for(loc.i = 0; loc.i < loc.objectsLength; loc.i++){
                loc.key = arguments.objects[loc.i + 1];
                loc.outputStream = createObject('java','java.io.ByteArrayOutputStream').init();
                arrayAppend(loc.returnValue,{'key' = loc.key, 'data' = loc.outputStream});
                loc.array.set(loc.downloadPackages,loc.i,$createJavaObject('org.jets3t.service.multi.DownloadPackage').init(
                        $createJavaObject('org.jets3t.service.model.S3Object').init(loc.key),
                        loc.outputStream
                    ));
            }

            $getThreadedService().downloadObjects(arguments.bucket,loc.downloadPackages);

            //Now go back through and get the text out
            for(loc.i = 1; loc.i <= loc.objectsLength; loc.i++){
                loc.returnValue[loc.i]['data'] = loc.returnValue[loc.i]['data'].toString('utf8');
            }

            return loc.returnValue;
        </cfscript>
    </cffunction>

    <cffunction name="$getThreadedService" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'simpleThreadedStorageService')){
    			lock timeout="20" name="awsthreadedservicelock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.multi.SimpleThreadedStorageService');
	    			loc.obj.init($getRestS3Service(arguments.reload));
	    			
	    			application.aws.simpleThreadedStorageService = loc.obj;
    			}
    		}

    		return application.aws.simpleThreadedStorageService;
    	</cfscript>
    </cffunction>

    <cffunction name="$getRestS3Service" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'restS3Service')){
    			lock timeout="20" name="awsrests3lock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.impl.rest.httpclient.RestS3Service');
	    			loc.obj.init($getAWSCredentials(arguments.reload),$null(),$null(),$getAWSProperties(arguments.reload));
	    			
	    			application.aws.restS3Service = loc.obj;
    			}
    		}

    		return application.aws.restS3Service;
    	</cfscript>
    </cffunction>

     <cffunction name="$getAWSProperties" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'awsProperties')){
    			lock timeout="20" name="awspropertieslock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.Jets3tProperties');
	    			loc.obj.init();
	    			//Set the properties
	    			if(structKeyExists(application.wheels,'aws.jets3tproperties')){
	    				loc.props = get('aws.jets3tproperties');
	    				for(loc.key in loc.props){
	    					loc.obj.setProperty(lcase(loc.key),'#loc.props[loc.key]#');
	    				}
	    			}
	    			
	    			application.aws.awsProperties = loc.obj;
    			}
    		}

    		return application.aws.awsProperties;
    	</cfscript>
    </cffunction>

    <cffunction name="$getAWSCredentials" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'awsCredentials')){
    			lock timeout="20" name="awscredentialslock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.security.AWSCredentials');
	    			loc.obj.init(get('aws.accessKeyId'),get('aws.secretAccessKey'));
	    			
	    			application.aws.awsCredentials = loc.obj;
    			}
    		}

    		return application.aws.awsCredentials;
    	</cfscript>
    </cffunction>

    <cffunction name="$getAWSServiceUtils" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'serviceUtils')){
    			lock timeout="20" name="awsserviceutilslock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.utils.ServiceUtils');
	    			
	    			application.aws.serviceUtils = loc.obj;
    			}
    		}

    		return application.aws.serviceUtils;
    	</cfscript>
    </cffunction>

    <cffunction name="$getAWSEncryptionUtil" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'encryptionutil')){
    			lock timeout="20" name="awsencryptionutillock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.security.EncryptionUtil');
	    			
	    			application.aws.encryptionutil = loc.obj;
    			}
    		}

    		return application.aws.encryptionutil;
    	</cfscript>
    </cffunction>

    <cffunction name="$createJavaObject" returntype="any" output="false">
    	<cfargument name="class" type="string" required="true"/>
    	<cfargument name="classpath" type="string" default="#application.aws.jars#"/>
    	<cfscript>
    		//First see if the class is already on the classpath
    		if($classExists(arguments.class)){
    			return createObject('java',arguments.class);
    		}

    		//Now check if it is railo
    		if(structKeyExists(server,'railo') && len(arguments.classpath)){
    			//We can pass the classpath directly here
    			return createObject('java',arguments.class,arguments.classpath);
    		}

    		//TODO: Check if Adobe Coldfusion here in the future. Either use JavaLoader.cfc or see if CF10's new features will work

    		$throw(type="Wheels.Unable to create java object", message="Unable to create the java object with class name: #arguments.class#. You may running on an unsupported engine.");
    	</cfscript>
    </cffunction>

    <cffunction name="$classExists" returntype="boolean" output="false">
    	<cfargument name="class" type="string" required="true"/>
    	<cfscript>
    		var loc = {};
    		loc.returnValue = true;
			try {
				loc.class = createObject('java','java.lang.Class').forName(arguments.class,false,$null());
			}
			catch(any e){
				loc.returnValue = false;
			}

			return loc.returnValue;
    	</cfscript>
    </cffunction>

    <cffunction name="$null" returntype="any" output="false">
    	<cfreturn javaCast("null","")/>
    </cffunction>

    <!--- Cloudfront specific items down here --->

    <!--- I would like to override the urlFor function here, but having two plugins override the same function is currently impossible with wheels. Look in to this later --->
    <cffunction name="cloudfrontSignedUrl" returntype="string" output="false">
    	<cfargument name="domain" type="string" required="true"/>
    	<cfargument name="path" type="string" required="true"/>
    	<cfargument name="protocol" type="string" required="false"/>
    	<cfargument name="timeout" type="numeric" required="false"/>
    	<cfargument name="dateLessThan" type="any" required="false"/>
    	<cfargument name="dateGreaterThan" type="any" required="false"/>
    	<cfargument name="ipAddress" type="string" required="false"/>
    	<cfargument name="policy" type="string" required="false"/>
    	<cfscript>
    		var loc = {};

    		//First build the url
    		if(!structKeyExists(arguments,'protocol') || arguments.protocol != 'https'){
    			arguments.protocol = 'http';
    		}
    		arguments.protocol = lcase(arguments.protocol);

    		loc.url = arguments.protocol & '://' & arguments.domain & '/' & arguments.path;

			
			//Passing in either of these arguments requires a policy to be created		
			if(structKeyExists(arguments,'dateGreaterThan') || structKeyExists(arguments,'ipAddress') || structKeyExists(arguments,'policy')){
				//Create the policy if not passed
				if(!structKeyExists(arguments,'policy')){
					arguments.policy = $cloudfrontPolicy(argumentCollection=arguments);
				}
				return $getCloudfrontService().signUrl(loc.url,get('aws.cloudfrontKeyPairId'),$getCloudfrontPrivateKey(),arguments.policy);
			}

			//We are creating a canned signed url
			return $getCloudFrontService().signUrlCanned(loc.url,get('aws.cloudfrontKeyPairId'),$getCloudfrontPrivateKey(),$cloudfrontFormatDate($calculateLessThanDate(argumentCollection=arguments)));

    	</cfscript>
    </cffunction>

    <cffunction name="$cloudfrontPolicy" returntype="any" output="false">
    	<cfargument name="path" type="string" default="#$null()#"/>
    	<cfargument name="timeout" type="numeric" required="false"/>
    	<cfargument name="dateLessThan" type="any" required="false"/>
    	<cfargument name="dateGreaterThan" type="any" default="#$null()#"/>
    	<cfargument name="ipAddress" type="any" default="#$null()#"/>
    	<cfscript>
    		arguments.dateLessThan = $calculateLessThanDate(argumentCollection=arguments);

			arguments.dateLessThan = $cloudfrontFormatDate(arguments.dateLessThan);
			arguments.dateGreaterThan = $cloudfrontFormatDate(arguments.dateGreaterThan);
			
			return $getCloudfrontService().buildPolicyForSignedUrl(
					arguments.path,
					arguments.dateLessThan,
					arguments.ipAddress,
					arguments.dateGreaterThan
				);

    	</cfscript>
    </cffunction>

    <cffunction name="$calculateLessThanDate" returntype="any" output="false">
    	<cfargument name="dateLessThan" type="any" required="false"/>
    	<cfargument name="timeout" type="numeric" required="false"/>
    	<cfscript>
			if(!structKeyExists(arguments,'dateLessThan')){
				if(!structKeyExists(arguments,'timeout')){
					if(structKeyExists(application.wheels,'aws.cloudfrontTimeout')){
						arguments.timeout = get('aws.cloudfrontTimeout');
					}
					else{
						arguments.timeout = 1800 //30 minute timeout default
					}
				}
				arguments.dateLessThan = dateAdd('s',arguments.timeout,now());
			}
			
			return arguments.dateLessThan;
    	</cfscript>
    </cffunction>

    <cffunction name="$cloudfrontFormatDate" returntype="string" output="false">
    	<cfargument name="date" type="any" required="true"/>
    	<cfscript>
    		if(isDate(arguments.date)){
    			arguments.date = dateConvert('local2Utc',arguments.date);
    			arguments.date = dateFormat(arguments.date,'yyyy-mm-dd') & 'T' & timeFormat(arguments.date,'HH:mm:ss.l') & 'Z';
    			arguments.date = $getAWSServiceUtils().parseIso8601Date(arguments.date);
    		}
    		return arguments.date;
    	</cfscript>
    </cffunction>

    <cffunction name="$getCloudfrontService" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'cloudfrontService')){
    			lock timeout="20" name="awsrests3lock" {
	    			//We need to create the java object
	    			loc.obj = $createJavaObject('org.jets3t.service.CloudFrontService');
	    			loc.obj.init($getAWSCredentials(arguments.reload));
	    			
	    			application.aws.cloudfrontService = loc.obj;
    			}
    		}

    		return application.aws.cloudfrontService;
    	</cfscript>
    </cffunction>

    <cffunction name="$getCloudfrontPrivateKey" returntype="any" output="false">
    	<cfargument name="reload" type="boolean" default="false"/>
    	<cfscript>
    		var loc = {};
    		loc.obj = false;
    		if(arguments.reload || !structKeyExists(application.aws,'cloudfrontprivatekey')){
    			lock timeout="20" name="awsprivatekeylock" {
	    			loc.privateKeyLocation = '';
	    			//First check if it was set in the config
	    			if(structKeyExists(application.wheels,'aws.cloudfrontkey')){
	    				loc.privateKeyLocation = get('aws.cloudfrontkey');
	    			}
	    			else{
	    				//Attempt to get it from the jvm arguments (fail silently)
	    				try{
	    					loc.privateKeyLocation = createObject("java", "java.lang.System").getProperty('AMAZON.CLOUDFRONT.KEY');
	    				}
	    				catch(any e){}
	    			}

	    			if(!len(loc.privateKeyLocation)){
	    				$throw(type="Wheels.Private key file unspecified", message="You need to specify the location of the private key file either in JVM arguments or the settings file.");
	    			}

	    			//Actually create it
	    			loc.inputStream = createObject('java','java.io.FileInputStream').init(loc.privateKeyLocation);
	    			application.aws.cloudfrontprivatekey = $getAWSEncryptionUtil().convertRsaPemToDer(loc.inputStream);
    			}
    		}

    		return application.aws.cloudfrontprivatekey;
    	</cfscript>
    </cffunction>

</cfcomponent>