#include "intersections.h"

__host__ __device__ float boxIntersectionTest(
    Geom box,
    Ray r,
    glm::vec3 &intersectionPoint,
    glm::vec3 &normal,
    bool &outside)
{
    Ray q;
    q.origin    =                multiplyMV(box.inverseTransform, glm::vec4(r.origin   , 1.0f));
    q.direction = glm::normalize(multiplyMV(box.inverseTransform, glm::vec4(r.direction, 0.0f)));

    float tmin = -1e38f;
    float tmax = 1e38f;
    glm::vec3 tmin_n;
    glm::vec3 tmax_n;
    for (int xyz = 0; xyz < 3; ++xyz)
    {
        float qdxyz = q.direction[xyz];
        /*if (glm::abs(qdxyz) > 0.00001f)*/
        {
            float t1 = (-0.5f - q.origin[xyz]) / qdxyz;
            float t2 = (+0.5f - q.origin[xyz]) / qdxyz;
            float ta = glm::min(t1, t2);
            float tb = glm::max(t1, t2);
            glm::vec3 n;
            n[xyz] = t2 < t1 ? +1 : -1;
            if (ta > 0 && ta > tmin)
            {
                tmin = ta;
                tmin_n = n;
            }
            if (tb < tmax)
            {
                tmax = tb;
                tmax_n = n;
            }
        }
    }

    if (tmax >= tmin && tmax > 0)
    {
        outside = true;
        if (tmin <= 0)
        {
            tmin = tmax;
            tmin_n = tmax_n;
            outside = false;
        }
        intersectionPoint = multiplyMV(box.transform, glm::vec4(getPointOnRay(q, tmin), 1.0f));
        normal = glm::normalize(multiplyMV(box.invTranspose, glm::vec4(tmin_n, 0.0f)));
        return glm::length(r.origin - intersectionPoint);
    }

    return -1;
}

__host__ __device__ float sphereIntersectionTest(
    Geom sphere,
    Ray r,
    glm::vec3 &intersectionPoint,
    glm::vec3 &normal,
    bool &outside)
{
    float radius = .5;

    glm::vec3 ro = multiplyMV(sphere.inverseTransform, glm::vec4(r.origin, 1.0f));
    glm::vec3 rd = glm::normalize(multiplyMV(sphere.inverseTransform, glm::vec4(r.direction, 0.0f)));

    Ray rt;
    rt.origin = ro;
    rt.direction = rd;

    float vDotDirection = glm::dot(rt.origin, rt.direction);
    float radicand = vDotDirection * vDotDirection - (glm::dot(rt.origin, rt.origin) - powf(radius, 2));
    if (radicand < 0)
    {
        return -1;
    }

    float squareRoot = sqrt(radicand);
    float firstTerm = -vDotDirection;
    float t1 = firstTerm + squareRoot;
    float t2 = firstTerm - squareRoot;

    float t = 0;
    if (t1 < 0 && t2 < 0)
    {
        return -1;
    }
    else if (t1 > 0 && t2 > 0)
    {
        t = min(t1, t2);
        outside = true;
    }
    else
    {
        t = max(t1, t2);
        outside = false;
    }

    glm::vec3 objspaceIntersection = getPointOnRay(rt, t);

    intersectionPoint = multiplyMV(sphere.transform, glm::vec4(objspaceIntersection, 1.f));
    normal = glm::normalize(multiplyMV(sphere.invTranspose, glm::vec4(objspaceIntersection, 0.f)));
    if (!outside)
    {
        normal = -normal;
    }

    return glm::length(r.origin - intersectionPoint);
}

__host__ __device__ float triangleIntersectionTest(Geom obj, 
    Triangle* triangles,
    Ray r,
    glm::vec3& intersectionPoint,
    glm::vec3& normal,
    bool& outside)
{
    if(!boundingBoxIntersectionTest(obj, r)){
        return -1;
    }

    glm::vec3 ro = multiplyMV(obj.inverseTransform, glm::vec4(r.origin, 1.0f));
    glm::vec3 rd = glm::normalize(multiplyMV(obj.inverseTransform, glm::vec4(r.direction, 0.0f)));

    float tmin = 1e9;
    Triangle minTri;
    glm::vec3 minBaryPos;

    //iterate all triangles
    for (int i = obj.triangleIndex; i < obj.triangleCount; i++)
    {
        Triangle& triangle = triangles[i];

        glm::vec3 baryPos;
        bool intersect = glm::intersectRayTriangle(ro, rd, triangle.vertices[0], triangle.vertices[1], triangle.vertices[2], baryPos);

        if (!intersect) continue;

        float t = baryPos.z;

        if (t < tmin && t > 0.0)
        {
            tmin = t;
            minTri = triangle;
            minBaryPos = baryPos;
        }
    }

    //identify the intersection point
    if (tmin < 1e9)
    {
        float b1 = minBaryPos[0];
        float b2 = minBaryPos[1];
        float b = 1 - b1 - b2;
        normal = b1 * minTri.normals[0] + b2 * minTri.normals[1] + b * minTri.normals[2];

        Ray tempR;
        tempR.origin = ro;
        tempR.direction = rd;
        glm::vec3 objspaceIntersection = getPointOnRay(tempR, tmin);

        intersectionPoint = multiplyMV(obj.transform, glm::vec4(objspaceIntersection, 1.f));
        normal = glm::normalize(multiplyMV(obj.invTranspose, glm::vec4(normal, 0.f)));

        outside = glm::dot(normal, rd) < 0;

        if (!outside)
        {
            normal = -normal;
        }

        return glm::length(r.origin - intersectionPoint);
    }

    return -1;
}

__host__ __device__ bool boundingBoxIntersectionTest(Geom obj,
    Ray r) {
    Ray q;
    q.origin = multiplyMV(obj.inverseTransform, glm::vec4(r.origin, 1.0f));
    q.direction = glm::normalize(multiplyMV(obj.inverseTransform, glm::vec4(r.direction, 0.0f)));

    float tmin = -1e10;
    float tmax = 1e10;
    glm::vec3 tmin_n, tmax_n;

    for (int i = 0; i < 3; i++) {
        float qc = q.direction[i];
        if (glm::abs(qc) > EPSILON) {
            float t1 = (obj.boundingBoxMin[i] - q.origin[i]) / qc;
            float t2 = (obj.boundingBoxMax[i] - q.origin[i]) / qc;
            float ta = glm::min(t1, t2);
            float tb = glm::max(t1, t2);
            glm::vec3 n;
            n[i] = t2 < t1 ? 1 : -1;
            if (ta > 0 && ta > tmin) {
                tmin = ta;
                tmin_n = n;
            }
            if (tb < tmax) {
                tmax = tb;
                tmax_n = n;
            }
        }
    }

    if (tmax >= tmin && tmax > 0) {
        return true;
    }

    return false;
}