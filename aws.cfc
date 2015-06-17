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

    <cffunction name="s3DownloadObject" returntype="any" output="true">
        <cfargument name="bucket" type="string" required="true"/>
        <cfargument name="key" type="string" required="true"/>
        <cfscript>
            var loc = {};
            loc.returnValue = '';
            loc.failCount = 0;

            do {
                // attempt to resolve sporadic errors.. try three times before abandoning
                try {
                    loc.obj = $getRestS3Service().getObject(arguments.bucket,arguments.key);    

                    loc.inputReader = createObject('java','java.io.InputStreamReader').init(loc.obj.getDataInputStream());
                    loc.scanner = createObject('java','java.util.Scanner').init(loc.inputReader);
                    
                    try{
                        loc.returnValue = loc.scanner.useDelimiter("\\A").next();
                    }
                    catch(any e){}
                } catch (any e) {
                    loc.failCount++;
                    if (loc.failCount > 2 || e.errorCode == "NoSuchKey") {
                        loc.message = e.type & " - " & e.message & " - " & e.errorCode & " - " & arguments.bucket & "/" & arguments.key;
                        throw(message=loc.message, type=e.type, errorcode=e.errorcode, detail=e.detail, extendedInfo=e.extendedInfo)
                    }
                }
            } while (loc.failCount > 0 && loc.failCount < 3);
           
            return loc.returnValue;
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
            loc.returnValue = [];
            loc.failCount = 0;

            do {
                try {
                    loc.objectsLength = arrayLen(arguments.objects);
                    loc.downloadPackageClass = $createJavaObject('org.jets3t.service.multi.DownloadPackage');
                    loc.array = $createJavaObject('java.lang.reflect.Array');
                    loc.downloadPackages = loc.array.newInstance(loc.downloadPackageClass.getClass(), loc.objectsLength);

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
                } catch (any e) {
                    loc.failCount++;
                    if (loc.failCount > 2) {
                        loc.message = e.type & " - " & e.message & " - " & e.errorCode & " - " & arguments.bucket & "/" & arguments.key;
                        throw(message=loc.message, type=e.type, errorcode=e.errorcode, detail=e.detail, extendedInfo=e.extendedInfo)
                    }
                }
            } while (loc.failCount > 0 && loc.failCount < 3);

            return loc.returnValue;
        </cfscript>
    </cffunction>

    <cffunction name="s3SignedUrl" returntype="string" output="false">
        <cfargument name="bucket" type="string" required="false"/>
        <cfargument name="key" type="string" required="false"/>
        <cfargument name="timeout" type="numeric" default="30"/>
        <cfargument name="dateExpiration" type="any" required="false"/>
        <cfscript>
            var loc = {};

            if(structKeyExists(arguments,'dateExpiration')){
                loc.expiryDate = arguments.dateExpiration;
            }
            else{
                loc.expiryDate = $calculateLessThanDate(argumentCollection=arguments)
            }

           return $getRestS3Service().createSignedGetUrl(arguments.bucket,arguments.key,$cloudfrontFormatDate(loc.expiryDate));
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
    	<cfargument name="domain" type="string" required="false"/>
    	<cfargument name="path" type="string" required="false"/>
    	<cfargument name="protocol" type="string" required="false"/>
        <cfargument name="url" type="string" required="false"/>
    	<cfargument name="timeout" type="numeric" required="false"/>
    	<cfargument name="dateLessThan" type="any" required="false"/>
    	<cfargument name="dateGreaterThan" type="any" required="false"/>
    	<cfargument name="ipAddress" type="string" required="false"/>
    	<cfargument name="policy" type="string" required="false"/>
    	<cfscript>
    		var loc = {};

            if(structKeyExists(arguments,'url')){
                loc.url = arguments.url;
            }
            else{
                //build the url
                if(!structKeyExists(arguments,'protocol') || arguments.protocol != 'https'){
                    arguments.protocol = 'http';
                }
                arguments.protocol = lcase(arguments.protocol);

                loc.url = arguments.protocol & '://' & arguments.domain & '/' & arguments.path;
            }
    		
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

    <cffunction name="uploadFileToS3" returntype="any" access="public" output="false">
        <cfargument name="bucket" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="acl" type="string" required="false" />

        <cfscript>
            loc.restService = $getRestS3Service();
            loc.file = $createJavaObject('java.io.File').init(arguments.path);
            loc.s3Object = $createJavaObject('org.jets3t.service.model.S3Object').init(loc.file);

            if (structKeyExists(arguments, "acl")) {
                loc.acl = $createJavaObject('org.jets3t.service.acl.AccessControlList');
                loc.s3Object.setAcl(loc.acl[arguments.acl]);
            }

            
            loc.restService.putObject(arguments.bucket, loc.s3Object)

            return;
        </cfscript>
        
    </cffunction>

    <!---
        Description:
            uploads a file on disk to a s3 bucket.
        Arguments:
            -> bucket: the bucket where the file is located.
            -> path: the path to the folder that contains the file. path should not include the file itself.
            -> file: the name of the actual file, ex: test.zip. used by default for the key of the s3Object.
            -> [optional] key: allows for manual specification of the s3Object key rather than using the default file argument.
            -> [optional] acl: specifies an AccessControlList object to set on an s3 object prior to upload. possible values:REST_CANNED_AUTHENTICATED_READ,REST_CANNED_PRIVATE  ,REST_CANNED_PUBLIC_READ,REST_CANNED_PUBLIC_READ_WRITE.
            -> [optional] canonicalGrantee: comma seperated list of canonical grantees to set on the acl.
            -> [optional] canonicalGranteePermissions: comma seperated list of permissions to set on canonical grantees. defaults to read only permissions. possible values: PERMISSION_FULL_CONTROL, PERMISSION_READ, PERMISSION_WRITE, PERMISSION_READ_ACP, PERMISSION_WRITE_ACP
     --->
    <cffunction name="$uploadFileToS3" returntype="any" access="public" output="false">
        <cfargument name="bucket" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="file" type="string" required="true" />
        <cfargument name="key" type="string" required="false" />
        <cfargument name="acl" type="string" required="false" />
        <cfargument name="aclRetries" type="numeric" default="3" />
        <cfargument name="canonicalGrantees" type="string" required="false" />
        <cfargument name="canonicalGranteePermissions" type="string" default="PERMISSION_READ" />

        <cfscript>
            // get the rest service object and load up a new s3Object using the passed path

            loc.restService = $getRestS3Service();
            loc.pathToFile = arguments.path & "/" & arguments.file;
            loc.file = $createJavaObject('java.io.File').init(loc.pathToFile);
            loc.s3Object = $createJavaObject('org.jets3t.service.model.S3Object').init(loc.file);

            // set the key of the s3Object

            loc.key = (structKeyExists(arguments, "key")) ? arguments.key : arguments.file;
            loc.s3Object.setKey(loc.key);

            if (structKeyExists(arguments, "acl")) {
                // set the object's acl based on the passed acl type

                loc.acl = $createJavaObject('org.jets3t.service.acl.AccessControlList')[arguments.acl];
                loc.s3Object.setAcl(loc.acl);
            }

            // upload the s3Object to the specified bucket

            loc.restService.putObject(arguments.bucket, loc.s3Object);
            
            if (structKeyExists(arguments, "acl")) {
                // set additional grantees and permissions

                loc.acl = {};
                loc.acl = loc.restService.getObjectAcl(arguments.bucket, loc.key);
                
                if (structKeyExists(arguments, "canonicalGrantees")) {
                    loc.canonicalGrantees = listToArray(arguments.canonicalGrantees);
                    loc.canonicalGranteePermissions = listToArray(arguments.canonicalGranteePermissions);
                    loc.permission = $createS3AclPermission();

                    for (loc.i = 1; loc.i <= arrayLen(loc.canonicalGrantees); loc.i++) {
                        // loop over canonicalGrantees

                        loc.canonicalGrantee = $createS3CanonicalGrantee(loc.canonicalGrantees[loc.i]);

                        for (loc.j = 1; loc.j <= arrayLen(loc.canonicalGranteePermissions); loc.j++)    {
                            // loop over canonicalGranteePermissions and set the canonical grantee + each passed permission on the acl

                            loc.acl.grantPermission(loc.canonicalGrantee, loc.permission[loc.canonicalGranteePermissions[loc.j]]);
                        }
                    }
                }

                for (loc.i = 1; loc.i <= arguments.aclRetries; loc.i++) {
                    // attempt to set the acl 3 times before throwing

                    loc.aclSet = true;
                    
                    try {
                        loc.restService.putObjectAcl(arguments.bucket, loc.key, loc.acl);
                    }
                    catch (any e) {
                        loc.aclSet = false;
                    }

                    if (loc.aclSet) {
                        break;
                    }

                    sleep(1000);
                }

                if (!loc.aclSet) {
                    throw("Failed to set ACL. [toString]:" & loc.acl.toString() & " [toXml]:" & loc.acl.toXml());
                }                
            }

            return;
        </cfscript>
        
    </cffunction>
    
    <!--- 
        Description:
            creates a CanonicalGrantee object
        Arguments:
            -> id: the id to be set on the CanonicalGrantee object
            -> [optional] displayName: the display name of the CanonicalGrantee object
     --->
    <cffunction name="$createS3CanonicalGrantee" returntype="any" access="public" output="false">
        <cfargument name="id" type="string" required="true" />
        <cfargument name="displayName" type="string" required="false" />

        <cfscript>
            var loc = {};
            loc.canonicalGrantee = $createJavaObject('org.jets3t.service.acl.CanonicalGrantee').init(arguments.id);

            if (structKeyExists(arguments, "displayName")) {
                loc.canonicalGrantee.setDisplayName(arguments.displayName);
            }

            return loc.canonicalGrantee;
        </cfscript>
        
    </cffunction>

    <!--- 
        Description:
            creates a Permission object
     --->
    <cffunction name="$createS3AclPermission" returntype="any" access="public" output="false">

        <cfscript>
            return $createJavaObject('org.jets3t.service.acl.Permission');
        </cfscript>
        
    </cffunction>

</cfcomponent>